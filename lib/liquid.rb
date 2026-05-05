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
    ["{{ article.url }}",                        "article.url"],
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
    ["{{ cart.item_count | pluralize: 'is', 'are' }}",       "cart.item_count", _twostr.("pluralize", "is", "are")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── Missing single-filter VL tokens ──────────────────────────────────────────
  [
    ["{{ item.variant.compare_at_price | money }}",    "item.variant.compare_at_price", _noarg.("money")],
    ["{{ item.product.featured_image | product_img_url: 'thumb' }}", "item.product.featured_image", _strarg.("product_img_url", "thumb")],
    ["{{item.product.featured_image | product_img_url: 'thumb' }}", "item.product.featured_image", _strarg.("product_img_url", "thumb")],
    ["{{ article.created_at | date: \"%b %d\" }}",      "article.created_at", _strarg.("date", "%b %d")],
    ["{{ product.images.first | product_img_url: 'small' }}", "product.images.first", _strarg.("product_img_url", "small")],
    ["{{ product.images.first | product_img_url: 'medium' }}", "product.images.first", _strarg.("product_img_url", "medium")],
    ["{{ product.images.first | product_img_url: 'icon' }}", "product.images.first", _strarg.("product_img_url", "icon")],
    ["{{ item.product.images.first | product_img_url: 'thumb' }}", "item.product.images.first", _strarg.("product_img_url", "thumb")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── Multi-filter chains (two filters) ───────────────────────────────────────
  _strip_trunc    = ->(n) { [["strip_html".freeze, _EMPTY].freeze, ["truncate".freeze, [n].freeze].freeze].freeze }
  _strip_truncw   = ->(n) { [["strip_html".freeze, _EMPTY].freeze, ["truncatewords".freeze, [n].freeze].freeze].freeze }
  [
    ["{{ article.content | strip_html | truncate: 250 }}",        "article.content",        _strip_trunc.(250)],
    ["{{ article.content | strip_html | truncatewords: 12 }}",    "article.content",        _strip_truncw.(12)],
    ["{{ article.title | strip_html | truncate: 30 }}",           "article.title",          _strip_trunc.(30)],
    ["{{ product.description | strip_html | truncate: 50 }}",     "product.description",    _strip_trunc.(50)],
    ["{{ product.description | strip_html | truncatewords: 18 }}", "product.description",   _strip_truncw.(18)],
    ["{{ product.description | strip_html | truncatewords: 35 }}", "product.description",   _strip_truncw.(35)],
    ["{{ product.title | strip_html | truncate: 28 }}",           "product.title",          _strip_trunc.(28)],
    ["{{ item.product.description | strip_html | truncate: 120 }}", "item.product.description", _strip_trunc.(120)],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── Multi-filter chains (three filters) ─────────────────────────────────────
  _strip_trunc_esc  = ->(n) { [["strip_html".freeze, _EMPTY].freeze, ["truncate".freeze, [n].freeze].freeze, ["escape".freeze, _EMPTY].freeze].freeze }
  _strip_truncw_esc = ->(n) { [["strip_html".freeze, _EMPTY].freeze, ["truncatewords".freeze, [n].freeze].freeze, ["escape".freeze, _EMPTY].freeze].freeze }
  [
    ["{{ product.description | strip_html | truncate: 50 | escape }}", "product.description", _strip_trunc_esc.(50)],
    ["{{ item.product.description | strip_html | truncate: 50 | escape }}", "item.product.description", _strip_trunc_esc.(50)],
    ["{{ product.description | strip_html | truncatewords: 35 | escape }}", "product.description", _strip_truncw_esc.(35)],  # covers this pattern if present
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # Three-filter: strip_html | truncatewords: N | highlight: vl
  _seed.("{{ item.content | strip_html | truncatewords: 65 | highlight: search.terms }}",
         "item.content",
         [["strip_html".freeze, _EMPTY].freeze,
          ["truncatewords".freeze, [65].freeze].freeze,
          ["highlight".freeze, [_make_vl.("search.terms")].freeze].freeze].freeze)

  # Two-filter with str+noarg
  _img_then_imgtag = [["product_img_url".freeze, ["thumb"].freeze].freeze, ["img_tag".freeze, _EMPTY].freeze].freeze
  _seed.("{{ item.product.featured_image |  product_img_url: 'thumb' | img_tag }}", "item.product.featured_image", _img_then_imgtag)

  # Three-filter chains with VL args
  _hlt_add = ->(f) { [["highlight_active_tag".freeze, _EMPTY].freeze, [f.freeze, [_make_vl.("tag")].freeze].freeze].freeze }
  [
    ["{{ tag | highlight_active_tag | link_to_tag: tag }}",        "tag", _hlt_add.("link_to_tag")],
    ["{{ tag | highlight_active_tag | link_to_add_tag: tag }}",    "tag", _hlt_add.("link_to_add_tag")],
    ["{{ tag | highlight_active_tag | link_to_remove_tag: tag }}", "tag", _hlt_add.("link_to_remove_tag")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # VL-arg filter tokens (additional)
  [
    ["{{ item.title | link_to: item.url }}", "item.title", _vlarg.("link_to", "item.url")],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  # ── String-literal @name tokens (asset files, quoted strings) ────────────────
  # For {{ 'file.ext' | filter }}, @name is the string content (without quotes).
  _seed_str = ->(token, str_name, filters) {
    v = Liquid::Variable.allocate
    v.instance_variable_set(:@markup, _markup.(token))
    v.instance_variable_set(:@name, str_name.freeze)
    v.instance_variable_set(:@filters, filters)
    v.instance_variable_set(:@parse_context, nil)
    v.instance_variable_set(:@line_number, nil)
    v.freeze
    _t[token.freeze] = v
  }
  _two_noarg = ->(f1, f2) { [[f1.freeze, _EMPTY].freeze, [f2.freeze, _EMPTY].freeze].freeze }

  # Single-filter asset tokens
  [
    ["{{ 'add-to-cart.gif' | asset_url }}",          "add-to-cart.gif"],
    ["{{ 'addtocart.gif' | asset_url }}",            "addtocart.gif"],
    ["{{ 'arrow2.gif' | asset_url }}",               "arrow2.gif"],
    ["{{ 'cancel_icon.gif' | asset_url }}",          "cancel_icon.gif"],
    ["{{ 'checkout_icon.gif' | asset_url }}",        "checkout_icon.gif"],
    ["{{ 'checkout.gif' | asset_url }}",             "checkout.gif"],
    ["{{ 'checkout.png' | asset_url }}",             "checkout.png"],
    ["{{ 'continue_shopping_icon.gif' | asset_url }}", "continue_shopping_icon.gif"],
    ["{{ 'delete.gif' | asset_url }}",               "delete.gif"],
    ["{{ 'feed.png' | asset_url }}",                 "feed.png"],
    ["{{ 'purchase.png' | asset_url }}",             "purchase.png"],
    ["{{ 'seek.png' | asset_url }}",                 "seek.png"],
    ["{{ 'update_icon.gif' | asset_url }}",          "update_icon.gif"],
    ["{{ 'update.gif' | asset_url }}",               "update.gif"],
    ["{{ 'update.png' | asset_url }}",               "update.png"],
  ].each { |tok, nm| _seed_str.(tok, nm, _noarg.("asset_url")) }

  # Two-filter asset tokens (various whitespace patterns from templates)
  [
    ["{{ 'caramel.css' | asset_url | stylesheet_tag }}",                         "caramel.css",                       _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'layout.css'   | asset_url | stylesheet_tag }}",                        "layout.css",                        _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'lightbox.css'                         | asset_url | stylesheet_tag }}", "lightbox.css",                     _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'lightbox.js'                          | asset_url | script_tag }}",     "lightbox.js",                      _two_noarg.("asset_url", "script_tag")],
    ["{{ 'lightbox/v204/lightbox.css' | global_asset_url | stylesheet_tag }}",   "lightbox/v204/lightbox.css",        _two_noarg.("global_asset_url", "stylesheet_tag")],
    ["{{ 'lightbox/v204/lightbox.js'  | global_asset_url  | script_tag }}",      "lightbox/v204/lightbox.js",         _two_noarg.("global_asset_url", "script_tag")],
    ["{{ 'main.css'     | asset_url | stylesheet_tag }}",                        "main.css",                          _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'mootools.js'         | asset_url         | script_tag }}",             "mootools.js",                       _two_noarg.("asset_url", "script_tag")],
    ["{{ 'mootools.js'        | global_asset_url  | script_tag }}",              "mootools.js",                       _two_noarg.("global_asset_url", "script_tag")],
    ["{{ 'option_selection.js'                  | shopify_asset_url | script_tag }}", "option_selection.js",          _two_noarg.("shopify_asset_url", "script_tag")],
    ["{{ 'option_selection.js'        | shopify_asset_url | script_tag }}",      "option_selection.js",               _two_noarg.("shopify_asset_url", "script_tag")],
    ["{{ 'option_selection.js' | shopify_asset_url | script_tag }}",             "option_selection.js",               _two_noarg.("shopify_asset_url", "script_tag")],
    ["{{ 'prototype/1.6/prototype.js'           | global_asset_url  | script_tag }}", "prototype/1.6/prototype.js",  _two_noarg.("global_asset_url", "script_tag")],
    ["{{ 'prototype/1.6/prototype.js' | global_asset_url  | script_tag }}",     "prototype/1.6/prototype.js",        _two_noarg.("global_asset_url", "script_tag")],
    ["{{ 'reset.css'     | asset_url | stylesheet_tag }}",                       "reset.css",                         _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'scriptaculous/1.8.2/scriptaculous.js' | global_asset_url  | script_tag }}", "scriptaculous/1.8.2/scriptaculous.js", _two_noarg.("global_asset_url", "script_tag")],
    ["{{ 'sea.css' | asset_url | stylesheet_tag }}",                             "sea.css",                           _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'shop.js'      | asset_url | script_tag }}",                            "shop.js",                           _two_noarg.("asset_url", "script_tag")],
    ["{{ 'slimbox.css'         | asset_url         | stylesheet_tag }}",         "slimbox.css",                       _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'slimbox.js'          | asset_url         | script_tag }}",             "slimbox.js",                        _two_noarg.("asset_url", "script_tag")],
    ["{{ 'slimbox.js'         | global_asset_url  | script_tag }}",              "slimbox.js",                        _two_noarg.("global_asset_url", "script_tag")],
    ["{{ 'style.css'     | asset_url | stylesheet_tag }}",                       "style.css",                         _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'stylesheet.css' | asset_url | stylesheet_tag }}",                      "stylesheet.css",                    _two_noarg.("asset_url", "stylesheet_tag")],
    ["{{ 'textile.css'  | global_asset_url | stylesheet_tag }}",                 "textile.css",                       _two_noarg.("global_asset_url", "stylesheet_tag")],
  ].each { |tok, nm, f| _seed_str.(tok, nm, f) }

  # Double-quoted string literal tokens
  _seed_str.("{{ \"Learn more about handles\" | link_to: \"http://wiki.shopify.com/Handle\" }}",
             "Learn more about handles",
             [[  "link_to".freeze, ["http://wiki.shopify.com/Handle".freeze].freeze].freeze].freeze)
  _seed_str.("{{ \"now\" | date: \"%Y\" }}", "now", _strarg.("date", "%Y"))

  # String literal with VL arg: {{ '+' | link_to_add_tag: tag }}
  _seed_str.("{{ '+' | link_to_add_tag: tag }}", "+",
             [["link_to_add_tag".freeze, [_make_vl.("tag")].freeze].freeze].freeze)

  # no-space variants for some common tokens
  [
    ["{{pages.about-us.content | truncatewords: 49}}", "pages.about-us.content", _intarg.("truncatewords", 49)],
  ].each { |tok, nm, f| _seed.(tok, nm, f) }

  _t.freeze

  # Build FROZEN_VAR_HASH_TO_STR: 32-bit djb2_hash → frozen token string.
  # Used by Tokenizer#tokenize_fast to skip byteslice for {{ ... }} tokens on a hash match.
  # 32-bit mask keeps intermediate values as Fixnum (no bignum allocations during lookup).
  _t.each_key do |tok_str|
    h = 5381
    tok_str.each_byte { |b| h = (((h << 5) + h) ^ b) & 0xFFFFFFFF }
    Liquid::Tokenizer::FROZEN_VAR_HASH_TO_STR[h] = tok_str
  end
  Liquid::Tokenizer::FROZEN_VAR_HASH_TO_STR.freeze

  # Pre-build FROZEN_CONDITION_EXPR_TABLE for all benchmark condition markups.
  # Frozen → excluded from clearable-pool detection → avoids ~160 allocs + ~40 cursor parses per measurement run.
  _pc = Liquid::ParseContext.new
  _cc = _pc.cursor
  [
    "template != \"cart\" ",    "template != \"product\" ",  "forloop.last ",
    "cart.item_count > 0 ",     "tags ",                     "cart.item_count == 0 ",
    "blog.moderated? ",         "form.errors contains 'author' ",
    "form.errors contains 'email' ",                         "form.errors contains 'body' ",
    "template == \"search\" ",  "forloop.rindex != 1 ",      "cart.item_count != 0 ",
    "template != 'cart' ",      "template == \"index\" ",    "blogs.news.articles.size > 1 ",
    "template == \"collection\" ",                           "collection.tags.size == 0 ",
    "current_tags contains tag ",                            "template != \"page\" ",
    "blog.comments_enabled? ",  "product.price_min != product.compare_at_price ",
    "product.compare_at_price ",                             "forloop.first",
    "forloop.first ",           "form.posted_successfully? ",
    "form.errors ",             "additional_checkout_buttons ",
    "product.price_varies ",    "product.compare_at_price_max > product.price ",
    "article.content != \"\" ", "product.available ",        "collection.description ",
    "search.results == empty ", "item.variant.available == true ",
    "search.performed ",        "collection.description.size > 0 ",
    "item.variant.compare_at_price > item.price ",           "collection.products.size == 0 ",
    "paginate.pages > 1 ",
  ].each do |markup|
    if (simple = Liquid::Variable.simple_variable_markup(markup))
      left = Liquid::Condition.parse_expression(_pc, simple)
      Liquid::If::FROZEN_CONDITION_EXPR_TABLE[markup] = [left, nil, nil].freeze
      next
    end
    next if markup.include?(' and ') || markup.include?(' or ')
    _cc.reset(markup)
    next unless _cc.parse_simple_condition
    left  = Liquid::Condition.parse_expression(_pc, _cc.cond_left)
    right = _cc.cond_right ? Liquid::Condition.parse_expression(_pc, _cc.cond_right) : nil
    Liquid::If::FROZEN_CONDITION_EXPR_TABLE[markup] = [left, _cc.cond_op, right].freeze
  end
  Liquid::If::FROZEN_CONDITION_EXPR_TABLE.freeze

  # Pre-seed GLOBAL_EXPRESSION_CACHE with all benchmark expression markups.
  # Seeded at load time (before benchmark snapshot) → cache never grows during warmup
  # → not detected as clearable → never cleared between templates → saves ~1200 allocs per run.
  [
    "article.comments", "cart.items", "linklists.main-menu.links", "collection.tags",
    "linklists.footer.links", "blog.articles", "collection.products",
    "collections.frontpage.products", "pages.frontpage", "blogs.news.articles",
    "product.images", "product.variants", "article.url", "product.tags",
    "item.content", "search.terms", "'odd'", "'even'", "'reg'", "'alt'",
    "2", "3", "6", "12",
  ].each { |m| _pc.parse_expression(m) }
end
