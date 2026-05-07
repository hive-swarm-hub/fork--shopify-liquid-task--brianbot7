# frozen_string_literal: true

require 'set'

module Liquid
  # StrainerTemplate is the computed class for the filters system.
  # New filters are mixed into the strainer class which is then instantiated for each liquid template render run.
  #
  # The Strainer only allows method calls defined in filters given to it via StrainerFactory.add_global_filter,
  # Context#add_filters or Template.register_filter
  class StrainerTemplate
    attr_writer :context

    def initialize(context)
      @context = context
    end

    class << self
      def add_filter(filter)
        return if include?(filter)

        invokable_non_public_methods = (filter.private_instance_methods + filter.protected_instance_methods).select { |m| invokable?(m) }
        if invokable_non_public_methods.any?
          raise MethodOverrideError, "Filter overrides registered public methods as non public: #{invokable_non_public_methods.join(', ')}"
        end

        include(filter)

        filter_methods.merge(filter.public_instance_methods.map(&:to_s))
        @invokable_cache = nil
      end

      def invokable?(method)
        cache = @invokable_cache ||= {}
        cached = cache[method]
        return cached unless cached.nil?
        key = method.instance_of?(String) ? method : method.to_s
        cache[method] = filter_methods.include?(key)
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@filter_methods, @filter_methods.dup)
        subclass.instance_variable_set(:@invokable_cache, nil)
      end

      def filter_method_names
        filter_methods.map(&:to_s).to_a
      end

      private

      def filter_methods
        @filter_methods ||= Set.new
      end
    end

    def invoke(method, *args)
      if self.class.invokable?(method)
        send(method, *args)
      elsif @context&.strict_filters
        raise Liquid::UndefinedFilter, "undefined filter #{method}"
      else
        args.first
      end
    rescue ::ArgumentError => e
      raise Liquid::ArgumentError, e.message, e.backtrace
    end

    # Fast path for single-argument (no extra args) filter invocation.
    # Avoids *args splat allocation for the common {{ value | filter }} case.
    def invoke_single(method, input)
      if self.class.invokable?(method)
        send(method, input)
      elsif @context&.strict_filters
        raise Liquid::UndefinedFilter, "undefined filter #{method}"
      else
        input
      end
    rescue ::ArgumentError => e
      raise Liquid::ArgumentError, e.message, e.backtrace
    end

    # Fast path for three-argument filter invocation (input + two args).
    def invoke_three(method, input, arg1, arg2)
      if self.class.invokable?(method)
        send(method, input, arg1, arg2)
      elsif @context&.strict_filters
        raise Liquid::UndefinedFilter, "undefined filter #{method}"
      else
        input
      end
    rescue ::ArgumentError => e
      raise Liquid::ArgumentError, e.message, e.backtrace
    end

    # Invoke with pre-built args array — dispatches by count to avoid splat allocation
    def invoke_array(method, input, args)
      unless self.class.invokable?(method)
        if @context&.strict_filters
          raise Liquid::UndefinedFilter, "undefined filter #{method}"
        end
        return input
      end
      case args.length
      when 0 then send(method, input)
      when 1 then send(method, input, args[0])
      when 2 then send(method, input, args[0], args[1])
      when 3 then send(method, input, args[0], args[1], args[2])
      else send(method, input, *args)
      end
    rescue ::ArgumentError => e
      raise Liquid::ArgumentError, e.message, e.backtrace
    end

    # Fast path for two-argument filter invocation (input + one arg).
    def invoke_two(method, input, arg1)
      if self.class.invokable?(method)
        send(method, input, arg1)
      elsif @context&.strict_filters
        raise Liquid::UndefinedFilter, "undefined filter #{method}"
      else
        input
      end
    rescue ::ArgumentError => e
      raise Liquid::ArgumentError, e.message, e.backtrace
    end
  end
end
