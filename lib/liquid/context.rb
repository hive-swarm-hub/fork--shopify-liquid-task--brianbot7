# frozen_string_literal: true

module Liquid
  # Context keeps the variable stack and resolves variables, as well as keywords
  #
  #   context['variable'] = 'testing'
  #   context['variable'] #=> 'testing'
  #   context['true']     #=> true
  #   context['10.2232']  #=> 10.2232
  #
  #   context.stack do
  #      context['bob'] = 'bobsen'
  #   end
  #
  #   context['bob']  #=> nil  class Context
  class Context
    attr_reader :scopes, :errors, :registers, :resource_limits, :static_registers, :static_environments
    attr_accessor :exception_renderer, :template_name, :partial, :global_filter, :strict_variables, :strict_filters, :environment

    # rubocop:disable Metrics/ParameterLists
    def self.build(environment: Environment.default, environments: {}, outer_scope: {}, registers: {}, rethrow_errors: false, resource_limits: nil, static_environments: {}, &block)
      new(environments, outer_scope, registers, rethrow_errors, resource_limits, static_environments, environment, &block)
    end

    # Fast-path constructor: accepts two environment hashes without allocating an intermediate Array.
    # Used by Template#render for the common (Hash assigns + template assigns) case.
    def self.new_for_render(env0, env1, outer_scope, registers, rethrow_errors, resource_limits, environment)
      obj = allocate
      obj.__send__(:init_for_render, env0, env1, outer_scope, registers, rethrow_errors, resource_limits, environment)
      obj
    end

    def environments
      @environments ||= @env1.nil? ? [@env0] : [@env0, @env1]
    end

    def initialize(environments = {}, outer_scope = {}, registers = {}, rethrow_errors = false, resource_limits = nil, static_environments = {}, environment = Environment.default)
      @environment = environment
      @environments = environments.is_a?(Array) ? environments : [environments]
      @env0 = @environments[0]
      @env1 = @environments[1]

      @static_environments = if static_environments.is_a?(Array)
        static_environments.frozen? ? static_environments : static_environments.freeze
      elsif static_environments.empty?
        Const::EMPTY_ARRAY
      else
        [static_environments].freeze
      end
      @scopes              = [outer_scope || {}]
      @registers           = registers.is_a?(Registers) ? registers : Registers.new(registers)
      @errors              = Const::EMPTY_ARRAY
      @partial             = false
      @strict_variables    = false
      @resource_limits     = resource_limits || ResourceLimits.new(environment.default_resource_limits)
      @base_scope_depth    = 0
      @interrupts          = Const::EMPTY_ARRAY
      @filters             = Const::EMPTY_ARRAY
      @global_filter       = nil
      @disabled_tags       = Const::EMPTY_HASH

      # Lazy-init StringScanner — only needed if Context#[] is called during render
      @string_scanner = nil

      @registers.static[:file_system] ||= environment.file_system

      self.exception_renderer = environment.exception_renderer
      if rethrow_errors
        self.exception_renderer = Liquid::RAISE_EXCEPTION_LAMBDA
      end

      yield self if block_given?

      # Do this last, since it could result in this object being passed to a Proc in the environment
      squash_instance_assigns_with_environments
    end
    # rubocop:enable Metrics/ParameterLists

    def warnings
      @warnings ||= []
    end

    def strainer
      @strainer ||= @environment.create_strainer(self, @filters)
    end

    # Adds filters to this context.
    #
    # Note that this does not register the filters with the main Template object. see <tt>Template.register_filter</tt>
    # for that
    def add_filters(filters)
      filters = [filters].flatten.compact
      @filters += filters
      @strainer = nil
    end

    def apply_global_filter(obj)
      global_filter.nil? ? obj : global_filter.call(obj)
    end

    # are there any not handled interrupts?
    def interrupt?
      !@interrupts.frozen? && !@interrupts.empty?
    end

    # push an interrupt to the stack. this interrupt is considered not handled.
    def push_interrupt(e)
      @interrupts = [] if @interrupts.frozen?
      @interrupts.push(e)
    end

    # pop an interrupt from the stack
    def pop_interrupt
      @interrupts.pop
    end

    def handle_error(e, line_number = nil)
      e = internal_error unless e.is_a?(Liquid::Error)
      e.template_name ||= template_name
      e.line_number   ||= line_number
      @errors = [] if @errors.frozen?
      @errors.push(e)
      exception_renderer.call(e).to_s
    end

    def invoke(method, *args)
      result = strainer.invoke(method, *args)
      if result.instance_of?(String) || result.instance_of?(Integer) || result.instance_of?(Float) || result.nil?
        result
      else
        result.to_liquid
      end
    end

    # Fast path for three-argument filter invocation (input + two args)
    def invoke_three(method, input, arg1, arg2)
      result = strainer.invoke_three(method, input, arg1, arg2)
      if result.instance_of?(String) || result.instance_of?(Integer) || result.instance_of?(Float) || result.nil?
        result
      else
        result.to_liquid
      end
    end

    # Invoke filter with pre-built args array — avoids splat allocation
    def invoke_array(method, input, args)
      result = strainer.invoke_array(method, input, args)
      if result.instance_of?(String) || result.instance_of?(Integer) || result.instance_of?(Float) || result.nil?
        result
      else
        result.to_liquid
      end
    end

    # Fast path for single-argument filter invocation (the most common case:
    # {{ value | filter }}) — avoids *args splat allocation.
    def invoke_single(method, input)
      result = strainer.invoke_single(method, input)
      if result.instance_of?(String) || result.instance_of?(Integer) || result.instance_of?(Float) || result.nil?
        result
      else
        result.to_liquid
      end
    end

    # Fast path for two-argument filter invocation (e.g. {{ value | default: 'x' }})
    def invoke_two(method, input, arg1)
      result = strainer.invoke_two(method, input, arg1)
      if result.instance_of?(String) || result.instance_of?(Integer) || result.instance_of?(Float) || result.nil?
        result
      else
        result.to_liquid
      end
    end

    # Push new local scope on the stack. use <tt>Context#stack</tt> instead
    def push(new_scope = {})
      @scopes.unshift(new_scope)
      check_overflow
    end

    # Merge a hash of variables in the current local scope
    def merge(new_scopes)
      @scopes[0].merge!(new_scopes)
    end

    # Pop from the stack. use <tt>Context#stack</tt> instead
    def pop
      raise ContextError if @scopes.size == 1
      @scopes.shift
    end

    # Pushes a new local scope on the stack, pops it at the end of the block
    #
    # Example:
    #   context.stack do
    #      context['var'] = 'hi'
    #   end
    #
    #   context['var']  #=> nil
    def stack(new_scope = {})
      push(new_scope)
      yield
    ensure
      pop
    end

    # Creates a new context inheriting resource limits, filters, environment etc.,
    # but with an isolated scope.
    def new_isolated_subcontext
      check_overflow

      self.class.build(
        environment: @environment,
        resource_limits: resource_limits,
        static_environments: static_environments,
        registers: Registers.new(registers),
      ).tap do |subcontext|
        subcontext.base_scope_depth   = base_scope_depth + 1
        subcontext.exception_renderer = exception_renderer
        subcontext.filters  = @filters
        subcontext.strainer = nil
        subcontext.errors   = errors
        subcontext.warnings = warnings
        subcontext.disabled_tags = @disabled_tags
      end
    end

    def clear_instance_assigns
      @scopes[0] = {}
    end

    # Only allow String, Numeric, Hash, Array, Proc, Boolean or <tt>Liquid::Drop</tt>
    def []=(key, value)
      @scopes[0][key] = value
    end

    # Look up variable, either resolve directly after considering the name. We can directly handle
    # Strings, digits, floats and booleans (true,false).
    # If no match is made we lookup the variable in the current scope and
    # later move up to the parent blocks to see if we can resolve the variable somewhere up the tree.
    # Some special keywords return symbols. Those symbols are to be called on the rhs object in expressions
    #
    # Example:
    #   products == empty #=> products.empty?
    def [](expression)
      evaluate(Expression.parse(expression, @string_scanner ||= StringScanner.new("")))
    end

    def key?(key)
      find_variable(key, raise_on_not_found: false) != nil
    end

    def evaluate(object)
      return object if object.instance_of?(String) || object.instance_of?(Integer) || object.instance_of?(Float)
      return object if object.nil? || object.equal?(true) || object.equal?(false)
      object.respond_to?(:evaluate) ? object.evaluate(self) : object
    end

    # Fetches an object starting at the local scope and then moving up the hierachy
    def find_variable(key, raise_on_not_found: true)
      # Fast path: check top scope first (most common in for loops)
      scope = @scopes[0]
      if scope.key?(key)
        variable = lookup_and_evaluate(scope, key, raise_on_not_found: raise_on_not_found)
      elsif @scopes.length == 1
        # Only one scope and key not found — go straight to environments
        variable = try_variable_find_in_environments(key, raise_on_not_found: raise_on_not_found)
      else
        # Multiple scopes — search through all of them
        scopes = @scopes
        found_scope = nil
        i = 1
        len = scopes.length
        while i < len
          if scopes[i].key?(key)
            found_scope = scopes[i]
            break
          end
          i += 1
        end

        variable = if found_scope
          lookup_and_evaluate(found_scope, key, raise_on_not_found: raise_on_not_found)
        else
          try_variable_find_in_environments(key, raise_on_not_found: raise_on_not_found)
        end
      end

      # update variable's context before invoking #to_liquid
      # Fast path: primitive types don't need context= or to_liquid conversion
      case variable
      when String, Integer, Float, NilClass, TrueClass, FalseClass
        return variable
      when Array, Hash, Time
        return variable
      end

      variable.context = self if variable.respond_to?(:context=)

      liquid_variable = variable.to_liquid

      if variable != liquid_variable
        liquid_variable.context = self if liquid_variable.respond_to?(:context=)
      end

      liquid_variable
    end

    def lookup_and_evaluate(obj, key, raise_on_not_found: true)
      value = obj[key]

      if value.nil? && @strict_variables && raise_on_not_found && obj.respond_to?(:key?) && !obj.key?(key)
        raise Liquid::UndefinedVariable, "undefined variable #{key}"
      end

      if value.instance_of?(Proc) && obj.respond_to?(:[]=)
        obj[key] = value.arity == 0 ? value.call : value.call(self)
      else
        value
      end
    end

    # Fast lookup: caller already verified key exists, skip strict_variables check
    def lookup_and_evaluate_existing(obj, key)
      value = obj[key]
      if value.instance_of?(Proc) && obj.respond_to?(:[]=)
        obj[key] = value.arity == 0 ? value.call : value.call(self)
      else
        value
      end
    end

    def with_disabled_tags(tag_names)
      @disabled_tags = {} if @disabled_tags.frozen?
      tag_names.each do |name|
        @disabled_tags[name] = @disabled_tags.fetch(name, 0) + 1
      end
      yield
    ensure
      tag_names.each do |name|
        @disabled_tags[name] -= 1
      end
    end

    def tag_disabled?(tag_name)
      @disabled_tags.fetch(tag_name, 0) > 0
    end

    protected

    attr_writer :base_scope_depth, :warnings, :errors, :strainer, :filters, :disabled_tags

    private

    attr_reader :base_scope_depth

    def try_variable_find_in_environments(key, raise_on_not_found:)
      # Fast path: @env0/@env1 are always set (both regular init and init_for_render).
      # This avoids Array access overhead from @environments.
      e0 = @env0
      if e0
        found_variable = lookup_and_evaluate(e0, key, raise_on_not_found: raise_on_not_found)
        return found_variable if !found_variable.nil? || @strict_variables && raise_on_not_found
        e1 = @env1
        if e1
          found_variable = lookup_and_evaluate(e1, key, raise_on_not_found: raise_on_not_found)
          return found_variable if !found_variable.nil? || @strict_variables && raise_on_not_found
        end
        # Fall through to static_environments if not found
      elsif (envs = @environments)
        len = envs.length
        i = 0
        while i < len
          found_variable = lookup_and_evaluate(envs[i], key, raise_on_not_found: raise_on_not_found)
          return found_variable if !found_variable.nil? || @strict_variables && raise_on_not_found
          i += 1
        end
      end
      static_envs = @static_environments
      len = static_envs.length
      return nil if len == 0
      i = 0
      while i < len
        found_variable = lookup_and_evaluate(static_envs[i], key, raise_on_not_found: raise_on_not_found)
        if !found_variable.nil? || @strict_variables && raise_on_not_found
          return found_variable
        end
        i += 1
      end
      nil
    end

    def check_overflow
      raise StackLevelError, "Nesting too deep" if overflow?
    end

    def overflow?
      base_scope_depth + @scopes.length > Block::MAX_DEPTH
    end

    def internal_error
      # raise and catch to set backtrace and cause on exception
      raise Liquid::InternalError, 'internal'
    rescue Liquid::InternalError => exc
      exc
    end

    def squash_instance_assigns_with_environments
      scope = @scopes.last
      return if scope.empty?
      scope.each_key do |k|
        e0 = @env0
        if e0
          if e0.key?(k)
            scope[k] = lookup_and_evaluate(e0, k)
            next
          end
          e1 = @env1
          if e1 && e1.key?(k)
            scope[k] = lookup_and_evaluate(e1, k)
          end
        else
          (@environments || []).each do |env|
            if env.key?(k)
              scope[k] = lookup_and_evaluate(env, k)
              break
            end
          end
        end
      end
    end # squash_instance_assigns_with_environments

    def init_for_render(env0, env1, outer_scope, registers, rethrow_errors, resource_limits, environment)
      @environment = environment
      @env0 = env0
      @env1 = env1
      @static_environments = Const::EMPTY_ARRAY
      @scopes = [outer_scope || {}]
      @registers = registers.is_a?(Registers) ? registers : Registers.new(registers)
      @errors = Const::EMPTY_ARRAY
      @partial = false
      @strict_variables = false
      @resource_limits = resource_limits || ResourceLimits.new(environment.default_resource_limits)
      @base_scope_depth = 0
      @interrupts = Const::EMPTY_ARRAY
      @filters = Const::EMPTY_ARRAY
      @global_filter = nil
      @disabled_tags = Const::EMPTY_HASH
      @string_scanner = nil
      @registers.static[:file_system] ||= environment.file_system
      self.exception_renderer = rethrow_errors ? Liquid::RAISE_EXCEPTION_LAMBDA : environment.exception_renderer
      squash_instance_assigns_with_environments
    end
  end # Context
end # Liquid
