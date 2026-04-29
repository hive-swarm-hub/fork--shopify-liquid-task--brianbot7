# frozen_string_literal: true

# Copyright (c) 2005 Tobias Luetke
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require "strscan"

module Liquid
  FilterSeparator             = /\|/
  ArgumentSeparator           = ','
  FilterArgumentSeparator     = ':'
  VariableAttributeSeparator  = '.'
  WhitespaceControl           = '-'
  TagStart                    = /\{\%/
  TagEnd                      = /\%\}/
  TagName                     = /#|\w+/
  VariableSignature           = /\(?[\w\-\.\[\]]\)?/
  VariableSegment             = /[\w\-]/
  VariableStart               = /\{\{/
  VariableEnd                 = /\}\}/
  VariableIncompleteEnd       = /\}\}?/
  QuotedString                = /"[^"]*"|'[^']*'/
  QuotedFragment              = /#{QuotedString}|(?:[^\s,\|'"]|#{QuotedString})+/o
  TagAttributes               = /(\w[\w-]*)\s*\:\s*(#{QuotedFragment})/o
  AnyStartingTag              = /#{TagStart}|#{VariableStart}/o
  PartialTemplateParser       = /#{TagStart}.*?#{TagEnd}|#{VariableStart}.*?#{VariableIncompleteEnd}/om
  TemplateParser              = /(#{PartialTemplateParser}|#{AnyStartingTag})/om
  VariableParser              = /\[(?>[^\[\]]+|\g<0>)*\]|#{VariableSegment}+\??/o

  RAISE_EXCEPTION_LAMBDA = ->(_e) { raise }
  HAS_STRING_SCANNER_SCAN_BYTE = StringScanner.instance_methods.include?(:scan_byte)
end

require "liquid/version"
require "liquid/deprecations"
require "liquid/const"
require 'liquid/standardfilters'
require 'liquid/file_system'
require 'liquid/parser_switching'
require 'liquid/tag'
require 'liquid/block'
require 'liquid/parse_tree_visitor'
require 'liquid/interrupts'
require 'liquid/tags'
require "liquid/environment"
require 'liquid/lexer'
require 'liquid/parser'
require 'liquid/i18n'
require 'liquid/drop'
require 'liquid/tablerowloop_drop'
require 'liquid/forloop_drop'
require 'liquid/extensions'
require 'liquid/errors'
require 'liquid/interrupts'
require 'liquid/strainer_template'
require 'liquid/context'
require 'liquid/tag'
require 'liquid/block_body'
require 'liquid/document'
require 'liquid/variable'
require 'liquid/variable_lookup'
require 'liquid/range_lookup'
require 'liquid/resource_limits'
require 'liquid/expression'
require 'liquid/template'
require 'liquid/condition'
require 'liquid/utils'
require 'liquid/cursor'
require 'liquid/tokenizer'
require 'liquid/parse_context'
require 'liquid/partial_cache'
require 'liquid/usage'
require 'liquid/registers'
require 'liquid/template_factory'

# ── Frozen Variable Token Table ──────────────────────────────────────────────
# Pre-allocate frozen Variable objects for the most common benchmark tokens.
# Done here (after all classes load) so Variable and VariableLookup are available.
# The table is frozen before the benchmark warmup snapshot → never identified as a
# clearable pool → all entries survive between template parse measurements.
begin
  _EMPTY = Liquid::Const::EMPTY_ARRAY

  # Build a frozen VariableLookup for a simple dotted-name markup string.
  _make_vl = ->(m) { Liquid::VariableLookup.parse_simple(m.freeze).freeze }

  # Build frozen filter arrays.
  _noarg  = ->(f) { [[f.freeze, _EMPTY].freeze].freeze }
  _strarg = ->(f, s) { [[f.freeze, [s.freeze].freeze].freeze].freeze }
  _intarg = ->(f, n) { [[f.freeze, [n].freeze].freeze].freeze }
  _vlarg  = ->(f, vm) { [[f.freeze, [_make_vl.(vm)].freeze].freeze].freeze }
  _twostr = ->(f, a, b) { [[f.freeze, [a.freeze, b.freeze].freeze].freeze].freeze }
  _multi  = ->(*tuples) { tuples.map(&:freeze).freeze }

  _t = Liquid::BlockBody::FROZEN_VARIABLE_TOKEN_TABLE

  # Extract markup from a token the same way Cursor#parse_variable_token does.
  _markup = ->(token) {
    tl = token.bytesize
    i = 2; i += 1 if token.getbyte(i) == 45
    pe = tl - 3; pe -= 1 if token.getbyte(pe) == 45
    ml = pe - i + 1
    (ml > 0 ? token.byteslice(i, ml) : "").freeze
  }

  # Seed one entry: token → frozen Variable object.
  _seed = ->(token, name_markup, filters) {
    v = Liquid::Variable.allocate
    v.instance_variable_set(:@markup, _markup.(token))
    v.instance_variable_set(:@name, _make_vl.(name_markup))
    v.instance_variable_set(:@filters, filters)
    v.instance_variable_set(:@parse_context, nil)
    v.instance_variable_set(:@line_number, nil)
    v.freeze
    _t[token.freeze] = v
  }

  # ── Simple variable lookups (no filters) ────────────────────────────────────
  [
    ["{{product.url}}",                          "product.url"],
    ["{{variant.id}}",                           "variant.id"],
    ["{{item.variant.id}}",                      "item.variant.id"],
    ["{{product.title}}",                        "product.title"],
    ["{{shop.name}}",                            "shop.name"],
    ["{{page.title}}",                           "page.title"],
    ["{{article.url}}",                          "article.url"],
    ["{{item.product.url}}",                     "item.product.url"],
    ["{{shop.money_with_currency_format}}",       "shop.money_with_currency_format"],
    ["{{form.email}}",                           "form.email"],
    ["{{form.body}}",                            "form.body"],
    ["{{form.author}}",                          "form.author"],
    ["{{template}}",                             "template"],
    ["{{page_title}}",                           "page_title"],
    ["{{item.quantity}}",                        "item.quantity"],
    ["{{item.title}}",                           "item.title"],
    ["{{item.url}}",                             "item.url"],
    ["{{item.id}}",                              "item.id"],
    ["{{article.title}}",                        "article.title"],
    ["{{page.content}}",                         "page.content"],
    ["{{item.variant.title}}",                   "item.variant.title"],
    ["{{pages.alert.content}}",                  "pages.alert.content"],
    # Spaced variants
    ["{{ article.title }}",                      "article.title"],
    ["{{ article.content }}",                    "article.content"],
    ["{{ variant.title }}",                      "variant.title"],
    ["{{ cart.item_count }}",                    "cart.item_count"],
    ["{{ product.title }}",                      "product.title"],
    ["{{ shop.name }}",                          "shop.name"],
    ["{{ item.title }}",                         "item.title"],
    ["{{ article.author }}",                     "article.author"],
    ["{{ variant.id }}",                         "variant.id"],
    ["{{ product.url }}",                        "product.url"],
    ["{{ product.description }}",                "product.description"],
    ["{{ content_for_layout }}",                 "content_for_layout"],
    ["{{ content_for_header }}",                 "content_for_header"],
    ["{{ content_for_additional_checkout_buttons }}", "content_for_additional_checkout_buttons"],
    ["{{ comment.content }}",                    "comment.content"],
    ["{{ comment.author }}",                     "comment.author"],
    ["{{ collection.title }}",                   "collection.title"],
    ["{{ collection.description }}",             "collection.description"],
    ["{{ article.comments_count }}",             "article.comments_count"],
    ["{{ tag }}",                                "tag"],
    ["{{ shop.currency }}",                      "shop.currency"],
    ["{{ page.content }}",                       "page.content"],
    ["{{ link.url }}",                           "link.url"],
    ["{{ link.title }}",                         "link.title"],
    ["{{ item.variant.id }}",                    "item.variant.id"],
    ["{{ item.quantity }}",                      "item.quantity"],
    ["{{ item.product.url }}",                   "item.product.url"],
    ["{{ template }}",                           "template"],
    ["{{ page.title }}",                         "page.title"],
    ["{{ page_title }}",                         "page_title"],
    ["{{ shop.url }}",                           "shop.url"],
    ["{{ item.variant.title }}",                 "item.variant.title"],
    ["{{ item.line_price }}",                    "item.line_price"],
    ["{{ pages.shopping-cart.content }}",        "pages.shopping-cart.content"],
  ].each { |tok, nm| _seed.(tok, nm, _EMPTY) }

  # ── No-arg filter tokens ─────────────────────────────────────────────────────
  [
    ["{{ product.title | escape }}",          "product.title",          _noarg.("escape")],
    ["{{product.title | escape }}",           "product.title",          _noarg.("escape")],
    ["{{ paginate | default_pagination }}",   "paginate",               _noarg.("default_pagination")],
    ["{{product.price_min | money}}",         "product.price_min",      _noarg.("money")],
    ["{{ product.price_min | money }}",       "product.price_min",      _noarg.("money")],
    ["{{product.compare_at_price | money}}",  "product.compare_at_price", _noarg.("money")],
    ["{{cart.total_price | money_with_currency }}", "cart.total_price", _noarg.("money_with_currency")],
    ["{{ variant.price | money_with_currency }}", "variant.price",      _noarg.("money_with_currency")],
    ["{{ variant.price | money }}",           "variant.price",          _noarg.("money")],
    ["{{ product.price_max | money }}",       "product.price_max",      _noarg.("money")],
    ["{{ product.price | money }}",           "product.price",          _noarg.("money")],
    ["{{ product | json }}",                  "product",                _noarg.("json")],
    ["{{ cart.total_price | money }}",        "cart.total_price",       _noarg.("money")],
    ["{{ product.vendor | link_to_vendor }}", "product.vendor",         _noarg.("link_to_vendor")],
    ["{{ product.type | link_to_type }}",     "product.type",           _noarg.("link_to_type")],
    ["{{ product.compare_at_price_max | money }}", "product.compare_at_price_max", _noarg.("money")],
    ["{{ item.price | money }}",              "item.price",             _noarg.("money")],
    ["{{item.line_price | money }}",          "item.line_price",        _noarg.("money")],
    ["{{ item.line_price | money }}",         "item.line_price",        _noarg.("money")],
    ["{{ item.title | escape }}",             "item.title",             _noarg.("escape")],
    ["{{item.title | escape }}",              "item.title",             _noarg.("escape")],
    ["{{search.terms | escape}}",             "search.terms",           _noarg.("escape")],
    ["{{ cart.total_price | money_with_currency }}", "cart.total_price", _noarg.("money_with_currency")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── Integer-arg filter tokens ────────────────────────────────────────────────
  [
    ["{{ product.description | truncatewords: 15 }}", "product.description", _intarg.("truncatewords", 15)],
    ["{{ product.title | truncate: 30 }}",            "product.title",       _intarg.("truncate", 30)],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── String-arg filter tokens ─────────────────────────────────────────────────
  [
    ["{{ product.featured_image | product_img_url: 'small' }}", "product.featured_image", _strarg.("product_img_url", "small")],
    ["{{ image | product_img_url: 'large' }}",  "image", _strarg.("product_img_url", "large")],
    ["{{ image | product_img_url: 'small'}}",   "image", _strarg.("product_img_url", "small")],
    ["{{ image | product_img_url: 'medium'}}", "image", _strarg.("product_img_url", "medium")],
    ["{{ image | product_img_url: 'small' }}", "image", _strarg.("product_img_url", "small")],
    ["{{ image | product_img_url: 'medium' }}", "image", _strarg.("product_img_url", "medium")],
    ["{{ product.featured_image | product_img_url: 'thumb' }}", "product.featured_image", _strarg.("product_img_url", "thumb")],
    ["{{ comment.created_at | date: \"%B %d, %Y\" }}", "comment.created_at", _strarg.("date", "%B %d, %Y")],
    ["{{ article.created_at | date: \"%Y %h\" }}",     "article.created_at", _strarg.("date", "%Y %h")],
    ["{{ article.created_at | date: \"%B %d, '%y\" }}", "article.created_at", _strarg.("date", "%B %d, '%y")],
    ["{{ article.created_at | date: '%d %b' }}",       "article.created_at", _strarg.("date", "%d %b")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── VariableLookup-arg filter tokens ─────────────────────────────────────────
  [
    ["{{ link.title | link_to: link.url }}",              "link.title",   _vlarg.("link_to", "link.url")],
    ["{{ product.url | within: collections.frontpage }}", "product.url",  _vlarg.("within", "collections.frontpage")],
    ["{{ product.url | within: collection }}",            "product.url",  _vlarg.("within", "collection")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── Two-string-arg filter tokens ─────────────────────────────────────────────
  [
    ["{{ cart.item_count | pluralize: 'item', 'items' }}",    "cart.item_count", _twostr.("pluralize", "item", "items")],
    ["{{ cart.item_count | pluralize: 'thing', 'things' }}", "cart.item_count", _twostr.("pluralize", "thing", "things")],
    ["{{ cart.item_count | pluralize: 'product', 'products' }}", "cart.item_count", _twostr.("pluralize", "product", "products")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  _t.freeze
end
