# frozen_string_literal: true

module Liquid
  # @liquid_public_docs
  # @liquid_type tag
  # @liquid_category iteration
  # @liquid_name for
  # @liquid_summary
  #   Renders an expression for every item in an array.
  # @liquid_description
  #   You can do a maximum of 50 iterations with a `for` loop. If you need to iterate over more than 50 items, then use the
  #   [`paginate` tag](/docs/api/liquid/tags/paginate) to split the items over multiple pages.
  #
  #   > Tip:
  #   > Every `for` loop has an associated [`forloop` object](/docs/api/liquid/objects/forloop) with information about the loop.
  # @liquid_syntax
  #   {% for variable in array %}
  #     expression
  #   {% endfor %}
  # @liquid_syntax_keyword variable The current item in the array.
  # @liquid_syntax_keyword array The array to iterate over.
  # @liquid_syntax_keyword expression The expression to render for each iteration.
  # @liquid_optional_param limit: [number] The number of iterations to perform.
  # @liquid_optional_param offset: [number] The 1-based index to start iterating at.
  # @liquid_optional_param range [untyped] A custom numeric range to iterate over.
  # @liquid_optional_param reversed [untyped] Iterate in reverse order.
  class For < Block
    Syntax = /\A(#{VariableSegment}+)\s+in\s+(#{QuotedFragment}+)\s*(reversed)?/o

    attr_reader :collection_name, :variable_name, :limit, :from

    # Cache parsed For markup: variable_name, collection_name, name, reversed, from, limit.
    # Markup strings are stable across re-parses of the same templates.
    GLOBAL_FOR_PARSE_CACHE = {}

    def initialize(tag_name, markup, options)
      super
      @from = @limit = nil
      parse_with_selected_parser(markup)
      @for_block = new_body
      @else_block = nil
    end

    def parse(tokens)
      if parse_body(@for_block, tokens)
        parse_body(@else_block, tokens)
      end
      if blank?
        @else_block&.remove_blank_strings
        @for_block.remove_blank_strings
      end
      @else_block&.freeze
      @for_block.freeze
    end

    def nodelist
      @else_block ? [@for_block, @else_block] : [@for_block]
    end

    def unknown_tag(tag, markup, tokens)
      return super unless tag == 'else'
      @else_block = new_body
    end

    def render_to_output_buffer(context, output)
      segment = collection_segment(context)

      if segment.empty?
        render_else(context, output)
      else
        render_segment(context, output, segment)
      end

      output
    end

    protected

    # Fast byte-level parser for "var in collection [reversed] [limit:N] [offset:N]"
    REVERSED_BYTES = "reversed".bytes.freeze

    def lax_parse(markup)
      if (cached = GLOBAL_FOR_PARSE_CACHE[markup])
        @variable_name   = cached[0]
        @collection_name = cached[1]
        @name            = cached[2]
        @reversed        = cached[3]
        @from            = cached[4]
        @limit           = cached[5]
        return
      end

      c = @parse_context.cursor
      c.reset(markup)
      c.skip_ws

      # Parse variable name
      var_start = c.pos
      var_len = c.skip_id
      raise SyntaxError, options[:locale].t("errors.syntax.for") if var_len == 0
      @variable_name = c.slice(var_start, var_len)

      # Expect "in"
      c.skip_ws
      raise SyntaxError, options[:locale].t("errors.syntax.for") unless c.expect_id("in")
      c.skip_ws

      # Parse collection name
      col_start = c.pos
      if c.peek_byte == Cursor::LPAREN
        # Parenthesized range: (1..10)
        depth = 1
        c.scan_byte
        while !c.eos? && depth > 0
          b = c.scan_byte
          depth += 1 if b == Cursor::LPAREN
          depth -= 1 if b == Cursor::RPAREN
        end
      else
        c.skip_fragment
      end
      collection_name = c.slice(col_start, c.pos - col_start)

      @name            = "#{@variable_name}-#{collection_name}"
      @collection_name = parse_expression(collection_name)

      c.skip_ws
      @reversed = c.expect_id("reversed")
      c.skip_ws

      # Parse limit:/offset: if present
      while !c.eos?
        c.skip_ws
        break if c.eos?
        if c.peek_byte == Cursor::COMMA
          c.scan_byte
          c.skip_ws
        end
        key = c.scan_id
        break unless key
        c.skip_ws
        break unless c.peek_byte == Cursor::COLON
        c.scan_byte
        c.skip_ws
        value = c.scan_fragment
        break unless value
        set_attribute(key, value)
      end

      GLOBAL_FOR_PARSE_CACHE[markup] = [@variable_name, @collection_name, @name, @reversed, @from, @limit].freeze
    end

    def strict_parse(markup)
      p = @parse_context.new_parser(markup)
      @variable_name = p.consume(:id)
      raise SyntaxError, options[:locale].t("errors.syntax.for_invalid_in") unless p.id?('in')

      collection_name  = p.expression
      @collection_name = parse_expression(collection_name, safe: true)

      @name     = "#{@variable_name}-#{collection_name}"
      @reversed = p.id?('reversed')

      while p.look(:comma) || p.look(:id)
        p.consume?(:comma)
        unless (attribute = p.id?('limit') || p.id?('offset'))
          raise SyntaxError, options[:locale].t("errors.syntax.for_invalid_attribute")
        end
        p.consume(:colon)
        set_attribute(attribute, p.expression, safe: true)
      end
      p.consume(:end_of_string)
    end

    private

    def strict2_parse(markup)
      strict_parse(markup)
    end

    def collection_segment(context)
      offsets = context.registers[:for] ||= {}

      from = if @from == :continue
        offsets[@name].to_i
      else
        from_value = context.evaluate(@from)
        if from_value.nil?
          0
        else
          Utils.to_integer(from_value)
        end
      end

      collection = context.evaluate(@collection_name)
      collection = collection.to_a if collection.is_a?(Range)

      limit_value = context.evaluate(@limit)
      to = if limit_value.nil?
        nil
      else
        Utils.to_integer(limit_value) + from
      end

      segment = Utils.slice_collection(collection, from, to)
      segment.reverse! if @reversed && segment.length > 1

      offsets[@name] = from + segment.length

      segment
    end

    def render_segment(context, output, segment)
      for_stack = context.registers[:for_stack] ||= []
      length    = segment.length

      # Reuse ForloopDrop and scope hash to avoid per-loop allocations
      loop_vars = @cached_loop_drop
      if loop_vars
        loop_vars.reset(@name, length, for_stack[-1])
      else
        loop_vars = (@cached_loop_drop = Liquid::ForloopDrop.new(@name, length, for_stack[-1]))
      end
      var_name = @variable_name
      scope = @cached_scope
      if scope
        scope.clear
        scope['forloop'] = loop_vars
        scope[var_name] = nil
      else
        scope = (@cached_scope = { 'forloop' => loop_vars, var_name => nil })
      end

      context.stack(scope) do
        for_stack.push(loop_vars)

        begin
          for_block = @for_block
          # Direct scope write avoids context[]= method dispatch overhead
          segment.each do |item|
            scope[var_name] = item
            for_block.render_to_output_buffer(context, output)
            loop_vars.increment!

            # Handle any interrupts if they exist.
            next unless context.interrupt?
            interrupt = context.pop_interrupt
            break if interrupt.is_a?(BreakInterrupt)
            next if interrupt.is_a?(ContinueInterrupt)
          end
        ensure
          for_stack.pop
        end
      end

      output
    end

    def set_attribute(key, expr, safe: false)
      case key
      when 'offset'
        @from = if expr == 'continue'
          :continue
        else
          parse_expression(expr, safe: safe)
        end
      when 'limit'
        @limit = parse_expression(expr, safe: safe)
      end
    end

    def render_else(context, output)
      if @else_block
        @else_block.render_to_output_buffer(context, output)
      else
        output
      end
    end

    class ParseTreeVisitor < Liquid::ParseTreeVisitor
      def children
        (super + [@node.limit, @node.from, @node.collection_name]).compact
      end
    end
  end
end
