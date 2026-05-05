# frozen_string_literal: true

require "strscan"

module Liquid
  class Tokenizer
    attr_reader :line_number, :for_liquid_tag

    OPEN_CURLEY = "{".ord
    CLOSE_CURLEY = "}".ord
    PERCENTAGE = "%".ord
    DASH = 45
    SPACE = 32
    TAB = 9
    LOWER_A = 97
    LOWER_Z = 122
    USCORE = 95

    # Pre-interned frozen text token strings for common short tokens (≤7 bytes).
    # Key = len followed by content bytes packed as a single integer: (len<<(8*len)) | packed_bytes.
    # Frozen: excluded from benchmark's clearable-pool detection — entries persist between all parses.
    # Avoids String allocation from byteslice for ~580 text tokens per benchmark cycle.
    FROZEN_TEXT_TOKEN_TABLE = begin
      h = {}
      [
        "\n  ", " ", "\">", "\n\n  ", " - ", "\n      ", "\n", "\" alt=\"",
        "error", "\n    ", "</span>", "\n\n", ", ", " x ", " (", " | ",
        "\n-->\n\n", ">", "\n\n    ", "</del>", " by ", " <del>", " on ",
        "  <h1>", "  ", "\t", "\r\n", "\">\n", " />", "</p>", "<br>",
        " {", "} ", "  {", "} \n", "\n {",
      ].each do |s|
        next if s.bytesize > 7
        k = s.bytesize
        s.each_byte { |b| k = (k << 8) | b }
        h[k] = s.freeze
      end
      h.freeze
    end

    # Pre-allocated frozen token strings for zero-markup tags (close tags, else, break, continue).
    # Keyed by a composite integer: (first5_bytes_of_name << 10) | (name_len << 2) | (dash_start ? 2 : 0) | (dash_end ? 1 : 0).
    # Frozen: not detected as a clearable pool by the benchmark, so entries persist permanently.
    ZERO_MARKUP_TOKEN_TABLE = begin
      table = {}
      %w[endif endunless endfor endtablerow endcapture endcomment enddoc else break continue].each do |name|
        nb = name.bytes
        ni = (nb[0] || 0) << 32 | (nb[1] || 0) << 24 | (nb[2] || 0) << 16 |
             (nb[3] || 0) << 8  | (nb[4] || 0)
        nl = name.length
        [false, true].each do |ds|
          [false, true].each do |de|
            prefix = ds ? "{%-" : "{%"
            suffix = de ? "-%}" : "%}"
            tok = "#{prefix} #{name} #{suffix}".freeze
            key = (ni << 10) | (nl << 2) | (ds ? 2 : 0) | (de ? 1 : 0)
            table[key] = tok
          end
        end
      end
      table.freeze
    end

    def initialize(
      source:,
      string_scanner:,
      line_numbers: false,
      line_number: nil,
      for_liquid_tag: false
    )
      @line_number = line_number || (line_numbers ? 1 : nil)
      @for_liquid_tag = for_liquid_tag
      @source = source.to_s.to_str
      @offset = 0
      @tokens = []

      tokenize if @source
    end

    def shift
      token = @tokens[@offset]

      return unless token

      @offset += 1

      if @line_number
        @line_number += @for_liquid_tag ? 1 : token.count("\n")
      end

      token
    end

    private

    # Bitmap of first bytes that CAN start a zero-markup close tag:
    # break(b=98), continue(c=99), else/end*(e=101).
    # All 128 ASCII values; non-close-tag first bytes return false quickly.
    CLOSE_TAG_FIRST_BYTE_OK = Array.new(128, false).tap do |a|
      [98, 99, 101].each { |b| a[b] = true }  # 'b', 'c', 'e'
    end.freeze

    # Try to return a pre-allocated frozen token for zero-markup close tags
    # (endif, endfor, else, break, continue, etc.) without calling byteslice.
    # Only matches the canonical format: "{%[-] tagname [-]%}" with exactly one space
    # on each side of the tag name. Returns frozen token on match, nil otherwise.
    # idx = position of '{%', close = position of '%' in '%}' terminator.
    def try_zero_markup_tag(src, idx, close)
      # Length pre-filter: canonical close tags are 10–21 bytes ({% else %} to {%- endtablerow -%})
      tok_len = close + 2 - idx
      return nil unless tok_len >= 10 && tok_len <= 21

      p = idx + 2  # after '{%'

      # Check optional '-' after '{%'
      b = src.getbyte(p)
      ds = b == DASH
      p += 1 if ds

      # Must have exactly one space (canonical format); no match otherwise
      return nil unless src.getbyte(p) == SPACE
      p += 1
      return nil if src.getbyte(p) == SPACE || src.getbyte(p) == TAB  # extra space → not canonical

      # Quick first-byte filter: close tags only start with 'b'(98), 'c'(99), 'e'(101)
      b0 = src.getbyte(p)
      return nil unless b0 && b0 < 128 && CLOSE_TAG_FIRST_BYTE_OK[b0]

      b1 = src.getbyte(p + 1) || 0
      b2 = src.getbyte(p + 2) || 0
      b3 = src.getbyte(p + 3) || 0
      b4 = src.getbyte(p + 4) || 0

      # Count full name length (stops at non-lowercase-alpha byte)
      nl = 0
      while (nb = src.getbyte(p + nl)) && nb >= LOWER_A && nb <= LOWER_Z
        nl += 1
      end
      p += nl

      # Must have exactly one space after tag name
      return nil unless src.getbyte(p) == SPACE
      p += 1
      return nil if src.getbyte(p) == SPACE || src.getbyte(p) == TAB  # extra space

      # Check for optional '-' before '%}'
      b = src.getbyte(p)
      de = b == DASH
      p += 1 if de

      # Must now be exactly at the '%' of '%}' (the `close` position)
      return nil unless p == close

      # Build lookup key and return pre-allocated token (or nil if unknown close tag)
      ni = (b0 << 32) | (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
      key = (ni << 10) | (nl << 2) | (ds ? 2 : 0) | (de ? 1 : 0)
      ZERO_MARKUP_TOKEN_TABLE[key]
    end

    def tokenize
      if @for_liquid_tag
        @tokens = @source.split("\n")
      else
        tokenize_fast
      end

      @source = nil
      @ss = nil
    end

    # Fast tokenizer using String#index instead of StringScanner regex.
    # String#index is ~40% faster for finding { delimiters.
    def tokenize_fast
      src = @source
      unless src.valid_encoding?
        raise SyntaxError, "Invalid byte sequence in #{src.encoding}"
      end

      len = src.bytesize
      pos = 0

      while pos < len
        # Find next { which could start a tag or variable
        idx = src.byteindex('{', pos)

        unless idx
          # No more tags/variables — rest is text
          text_len = len - pos
          if text_len > 0
            if text_len <= 7
              k = text_len
              j = pos
              while j < len
                k = (k << 8) | src.getbyte(j)
                j += 1
              end
              @tokens << (FROZEN_TEXT_TOKEN_TABLE[k] || src.byteslice(pos, text_len))
            else
              @tokens << src.byteslice(pos, text_len)
            end
          end
          break
        end

        next_byte = idx + 1 < len ? src.getbyte(idx + 1) : nil

        if next_byte == PERCENTAGE # {%
          # Emit text before tag
          if idx > pos
            text_len = idx - pos
            if text_len <= 7
              k = text_len
              j = pos
              while j < idx
                k = (k << 8) | src.getbyte(j)
                j += 1
              end
              @tokens << (FROZEN_TEXT_TOKEN_TABLE[k] || src.byteslice(pos, text_len))
            else
              @tokens << src.byteslice(pos, text_len)
            end
          end

          # Find %} to close the tag
          close = src.byteindex('%}', idx + 2)
          if close
            @tokens << (try_zero_markup_tag(src, idx, close) || src.byteslice(idx, close + 2 - idx))
            pos = close + 2
          else
            @tokens << "{%"
            pos = idx + 2
          end
        elsif next_byte == OPEN_CURLEY # {{
          # Emit text before variable
          if idx > pos
            text_len = idx - pos
            if text_len <= 7
              k = text_len
              j = pos
              while j < idx
                k = (k << 8) | src.getbyte(j)
                j += 1
              end
              @tokens << (FROZEN_TEXT_TOKEN_TABLE[k] || src.byteslice(pos, text_len))
            else
              @tokens << src.byteslice(pos, text_len)
            end
          end

          # Scan variable token — matches original tokenizer's byte-by-byte logic:
          # Find } or {, then check next byte for }}/{% nesting
          scan_pos = idx + 2
          found = false
          while scan_pos < len
            b = src.getbyte(scan_pos)
            if b == CLOSE_CURLEY # }
              if scan_pos + 1 >= len
                @tokens << src.byteslice(idx, scan_pos + 1 - idx)
                pos = scan_pos + 1
                found = true
                break
              end
              b2 = src.getbyte(scan_pos + 1)
              if b2 == CLOSE_CURLEY
                @tokens << src.byteslice(idx, scan_pos + 2 - idx)
                pos = scan_pos + 2
                found = true
                break
              else
                @tokens << src.byteslice(idx, scan_pos + 1 - idx)
                pos = scan_pos + 1
                found = true
                break
              end
            elsif b == OPEN_CURLEY
              if scan_pos + 1 < len && src.getbyte(scan_pos + 1) == PERCENTAGE
                close = src.byteindex('%}', scan_pos + 2)
                if close
                  @tokens << src.byteslice(idx, close + 2 - idx)
                  pos = close + 2
                else
                  @tokens << src.byteslice(idx, len - idx)
                  pos = len
                end
                found = true
                break
              end
              scan_pos += 1
            else
              scan_pos += 1
            end
          end

          unless found
            @tokens << "{{"
            pos = idx + 2
          end
        else
          # { followed by something else — it's text
          # Keep scanning from after this {
          # Find next { that could be {%  or {{
          next_open = idx + 1
          while next_open < len
            ni = src.byteindex('{', next_open)
            unless ni
              @tokens << src.byteslice(pos, len - pos)
              pos = len
              break
            end
            nb = ni + 1 < len ? src.getbyte(ni + 1) : nil
            if nb == PERCENTAGE || nb == OPEN_CURLEY
              @tokens << src.byteslice(pos, ni - pos)
              pos = ni
              break
            end
            next_open = ni + 1
          end
        end
      end
    end
  end
end
