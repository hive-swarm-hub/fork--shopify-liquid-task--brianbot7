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

  # Pre-build FROZEN_LONG_TEXT_TABLE with benchmark text tokens > 7 bytes.
  # Hard-coded from actual tokenizer output — frozen at load time so the pool-clearing
  # mechanism never clears it between measurement runs. Layouts reused ~7x each,
  # so each layout text token would otherwise allocate 7x per run.
  [
    "<div class=\"article\">\n  <h2 class=\"article-title\">",
    "</h2>\n  <p class=\"article-details\">posted <span class=\"article-time\">",
    "</span> by <span class=\"article-author\">",
    "</span></p>\n\n  <div class=\"article-body textile\">\n    ",
    "\n  </div>\n\n</div>\n\n<!-- Comments -->\n",
    "\n<div id=\"comments\">\n  <h3>Comments</h3>\n\n  <!-- List all comments -->\n  <ul id=\"comment-list\">\n  ",
    "\n    <li>\n      <div class=\"comment-details\">\n        <span class=\"comment-author\">",
    "</span> said on <span class=\"comment-date\">",
    "</span>:\n      </div>\n\n      <div class=\"comment\">\n        ",
    "\n      </div>\n    </li>\n  ",
    "\n  </ul>\n\n  <!-- Comment Form -->\n  <div id=\"comment-form\">\n  ",
    "\n    <h3>Leave a comment</h3>\n\n    <!-- Check if a comment has been submitted in the last request, and if yes display an appropriate message -->\n    ",
    "\n        <div class=\"notice\">\n          Successfully posted your comment.<br />\n          It will have to be approved by the blog owner first before showing up.\n        </div>\n      ",
    "\n        <div class=\"notice\">Successfully posted your comment.</div>\n      ",
    "\n      <div class=\"notice error\">Not all the fields have been filled out correctly!</div>\n    ",
    "\n\n    <dl>\n      <dt class=\"",
    "\"><label for=\"comment_author\">Your name</label></dt>\n      <dd><input type=\"text\" id=\"comment_author\" name=\"comment[author]\" size=\"40\" value=\"",
    "\" class=\"",
    "input-error",
    "\" /></dd>\n\n      <dt class=\"",
    "\"><label for=\"comment_email\">Your email</label></dt>\n      <dd><input type=\"text\" id=\"comment_email\" name=\"comment[email]\" size=\"40\" value=\"",
    "\"><label for=\"comment_body\">Your comment</label></dt>\n      <dd><textarea id=\"comment_body\" name=\"comment[body]\" cols=\"40\" rows=\"5\" class=\"",
    "</textarea></dd>\n    </dl>\n\n    ",
    "\n      <p class=\"hint\">comments have to be approved before showing up</p>\n    ",
    "\n\n    <input type=\"submit\" value=\"Post comment\" id=\"comment-submit\" />\n  ",
    "\n  </div>\n  <!-- END Comment Form -->\n\n</div>\n",
    "\n<!-- END Comments -->\n",
    "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"\n  \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n\n<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">\n<head>\n  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"/>\n  <title>",
    "</title>\n\n  ",
    "\n</head>\n\n<body id=\"page-",
    "\">\n\n  <p class=\"hide\"><a href=\"#rightsiders\">Skip to navigation.</a></p>\n    <!-- mini cart -->\n        ",
    "\n      <div id=\"minicart\" style=\"display:none;\"><div id=\"minicart-inner\">\n      <div id=\"minicart-items\">\n      <h2>There ",
    " in <a href=\"/cart\" title=\"View your cart\">your cart</a>!</h2><h4 style=\"font-size: 16px; margin: 0 0 10px 0; padding: 0;\">Your subtotal is ",
    ".</h4>\n        ",
    "\n        <div class=\"thumb\">\n          <div class=\"prodimage\"><a href=\"",
    "\" onMouseover=\"tooltip('",
    ")', 200)\"; onMouseout=\"hidetooltip()\"><img src=\"",
    "\" /></a></div>\n        </div>\n        ",
    "\n        </div>\n       <br style=\"clear:both;\" />\n      </div></div>\n        ",
    "\n\n  <div id=\"container\">\n    <div id=\"header\">\n      <!-- Begin Header -->\n        <h1 id=\"logo\"><a href=\"/\" title=\"Go Home\">",
    "</a></h1>\n      <div id=\"cartlinks\">\n        ",
    "\n          <h2 id=\"cartcount\"><a href=\"/cart\" onMouseover=\"tooltip('There ",
    " in your cart!', 200)\"; onMouseout=\"hidetooltip()\">",
    "!</a></h2>\n      <a href=\"/cart\" id=\"minicartswitch\" onclick=\"superSwitch(this, 'minicart', 'Close Mini Cart'); return false;\" id=\"cartswitch\">View Mini Cart (",
    ")</a>\n        ",
    "\n      </div>\n      <!-- End Header -->\n\n    </div>\n  <hr />\n<div id=\"main\">\n\n    <div id=\"content\">\n    <div id=\"innercontent\">\n      ",
    "\n      </div>\n    </div>\n\n  <hr />\n    <div id=\"rightsiders\">\n\n      <ul class=\"rightlinks\">\n        ",
    "\n           <li>",
    "</li>\n        ",
    "\n      </ul>\n\n        ",
    "\n        <ul class=\"rightlinks\">\n          ",
    "\n            <li><span class=\"add-link\">",
    "</li>\n          ",
    "\n        </ul>\n        ",
    "\n\n      <ul class=\"rightlinks\">\n        ",
    "\n      </ul>\n\n    </div>\n\n  <hr /><br style=\"clear:both;\" />\n\n    <div id=\"footer\">\n      <div class=\"footerinner\">\n      All prices are in ",
    ".\n      Powered by <a href=\"http://www.shopify.com\" title=\"Shopify, Hosted E-Commerce\">Shopify</a>.\n    </div>\n    </div>\n\n  </div>\n</div>\n\n<div id=\"tooltip\"></div>\n<img id=\"pointer\" src=\"",
    "\" />\n\n</body>\n</html>\n\n",
    "<div id=\"page\">\n  <h2>",
    "</h2>\n\n  ",
    "\n\n    <div class=\"article\">\n      <div class=\"headline\">\n      <h3 class=\"title\">\n        <a href=\"",
    "</a>\n      </h3>\n      <h4 class=\"date\">Posted on ",
    ".</h4>\n      </div>\n\n      <div class=\"article-body textile\">\n        ",
    "\n      </div>\n\n      ",
    "\n        <p style=\"text-align: right\"><a href=\"",
    "#comments\">",
    " comments</a></p>\n      ",
    "\n    </div>\n\n    ",
    "\n\n    <div id=\"pagination\">\n      ",
    "\n    </div>\n\n  ",
    "\n\n</div>\n",
    "<script type=\"text/javascript\">\n  function remove_item(id) {\n      document.getElementById('updates_'+id).value = 0;\n      document.getElementById('cartform').submit();\n  }\n</script>\n\n<div>\n\n  ",
    "\n    <h4>Your shopping cart is looking rather empty...</h4>\n  ",
    "\n  <form action=\"/cart\" method=\"post\" id=\"cartform\">\n\n  <div id=\"cart\">\n\n  <h3>You have ",
    " in here!</h3>\n\n    <ul id=\"line-items\">\n      ",
    "\n      <li id=\"item-",
    "\" class=\"clearfix\">\n        <div class=\"thumb\">\n          <div class=\"prodimage\">\n          <a href=\"",
    "\" title=\"View ",
    " Page\"><img src=\"",
    "\" /></a>\n        </div></div>\n        <h3 style=\"padding-right: 150px\">\n      <a href=\"",
    " Page\">\n        ",
    "\n        ",
    "\n           (",
    ")\n        ",
    "\n      </a>\n    </h3>\n        <small class=\"itemcost\">Costs ",
    " each, <span class=\"money\">",
    "</span> total.</small>\n        <p class=\"right\">\n          <label for=\"updates\">How many? </label>\n          <input type=\"text\" size=\"4\" name=\"updates[",
    "]\" id=\"updates_",
    "\" value=\"",
    "\" onfocus=\"this.select();\"/><br />\n          <a href=\"#\" onclick=\"remove_item(",
    "); return false;\" class=\"remove\"><img style=\"padding:15px 0 0 0;margin:0;\" src=\"",
    "\" /></a>\n        </p>\n      </li>\n      ",
    "\n      <li id=\"total\">\n        <input type=\"image\" id=\"update-cart\" name=\"update\" value=\"Update My Cart\" src=\"",
    "\" />\n        Subtotal:\n        <span class=\"money\">",
    "</span>\n      </li>\n    </ul>\n\n  </div>\n\n    <div class=\"info\">\n    <input type=\"image\" value=\"Checkout!\" name=\"checkout\" src=\"",
    "\" />\n    </div>\n\n    ",
    "\n    <div class=\"additional-checkout-buttons\">\n      <p>- or -</p>\n      ",
    "\n    </div>\n    ",
    "\n\n  </form>\n\n  ",
    "\n\n<ul id=\"product-collection\">\n    ",
    "\n    <li class=\"singleproduct clearfix\">\n      <div class=\"small\">\n        <div class=\"prodimage\"><a href=\"",
    "\"><img src=\"",
    "\" /></a></div>\n      </div>\n      <div class=\"description\">\n        <h3><a href=\"",
    "</a></h3>\n        <p>",
    "</p>\n      <p class=\"money\">",
    "</p>\n     </div>\n    </li>\n    ",
    "\n</ul>\n\n<div id=\"pagination\">\n  ",
    "\n</div>\n\n",
    "<div id=\"frontproducts\"><div id=\"frontproducts-top\"><div id=\"frontproducts-bottom\">\n<h2 style=\"display: none;\">Featured Items</h2>\n",
    "\n  <div class=\"productmain\">\n   <a href=\"",
    "\" /></a>\n   <h3><a href=\"",
    "</a></h3>\n   <div class=\"description\">",
    "</div>\n  <p class=\"money\">",
    "</p>\n  </div>\n",
    "\n  <div class=\"product\">\n   <a href=\"",
    "</a></h3>\n     <p class=\"money\">",
    "\n</div></div></div>\n\n<div id=\"mainarticle\">\n  ",
    "\n    <h2>",
    "</h2>\n    <div class=\"article-body textile\">\n      ",
    "\n    </div>\n  ",
    "\n    <div class=\"article-body textile\">\n    In <em>Admin &gt; Blogs &amp; Pages</em>, create a page with the handle <strong><code>frontpage</code></strong> and it will show up here.<br />\n    ",
    "\n\n</div>\n<br style=\"clear: both;\" />\n<div id=\"articles\">\n  ",
    "\n    <div class=\"article\">\n    <h2>",
    "\n    </div>\n  </div>\n  ",
    "</h2>\n\n  <div class=\"article textile\">\n    ",
    "\n  </div>\n\n</div>\n",
    "<div id=\"productpage\">\n\n  <div id=\"productimages\"><div id=\"productimages-top\"><div id=\"productimages-bottom\">\n    ",
    "\n        <a href=\"",
    "\" class=\"productimage\" rel=\"lightbox\">\n          <img src=\"",
    "\" />\n        </a>\n      ",
    "\" class=\"productimage-small\" rel=\"lightbox\">\n          <img src=\"",
    "\n  </div></div></div>\n\n  <h2>",
    "</h2>\n\n  <ul id=\"details\" class=\"hlist\">\n    <li>Vendor: ",
    "</li>\n    <li>Type: ",
    "</li>\n  </ul>\n\n  <small>",
    "</small>\n\n  <div id=\"variant-add\">\n    <form action=\"/cart/add\" method=\"post\">\n\n      <select id=\"variant-select\" name=\"id\" class=\"product-info-options\">\n        ",
    "\n          <option value=\"",
    "</option>\n        ",
    "\n      </select>\n\n      <div id=\"price-field\" class=\"price\"></div>\n\n    <div style=\"text-align:center;\"><input type=\"image\" name=\"add\" value=\"Add to Cart\" id=\"add\" src=\"",
    "\" /></div>\n    </form>\n  </div>\n\n  <div class=\"description textile\">\n    ",
    "\n  </div>\n</div>\n\n<script type=\"text/javascript\">\n<!--\n  // prototype callback for multi variants dropdown selector\n  var selectCallback = function(variant, selector) {\n    if (variant && variant.available == true) {\n      // selected a valid variant\n      $('add').removeClassName('disabled'); // remove unavailable class from add-to-cart button\n      $('add').disabled = false;           // reenable add-to-cart button\n      $('price-field').innerHTML = Shopify.formatMoney(variant.price, \"",
    "\");  // update price field\n    } else {\n      // variant doesn't exist\n      $('add').addClassName('disabled');      // set add-to-cart button to unavailable class\n      $('add').disabled = true;              // disable add-to-cart button\n      $('price-field').innerHTML = (variant) ? \"Sold Out\" : \"Unavailable\"; // update price-field message\n    }\n  };\n\n  // initialize multi selector for product\n  Event.observe(document, 'dom:loaded', function() {\n    new Shopify.OptionSelectors(\"variant-select\", { product: ",
    ", onVariantSelected: selectCallback });\n  });\n-->\n</script>\n",
    "\n    <li>\n      <div class=\"comment\">\n        ",
    "\n      </div>\n\n      <div class=\"comment-details\">\n        Posted by ",
    "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n<html xmlns=\"http://www.w3.org/1999/xhtml\" lang=\"en\">\n<head>\n  <title>",
    "</title>\n  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n\n  ",
    "\n </head>\n\n<body id=\"page-",
    "\">\n<p class=\"hide\"><a href=\"#navigation\">Skip to navigation.</a></p>\n<div id=\"wrapper\">\n  <div class=\"content clearfix\">\n    <div id=\"header\">\n      <h2><a href=\"/\">",
    "</a></h2>\n    </div>\n    <div id=\"left-col\">\n      ",
    "\n    </div>\n    <div id=\"right-col\">\n      ",
    "\n          <div id=\"cart-right-col\">\n          <dl id=\"cart-right-col-info\">\n            <dt>Shopping Cart</dt>\n            <dd>\n            ",
    "\n              <a href=\"/cart\">",
    "</a> in your cart\n            ",
    "\n              Your cart is empty\n            ",
    "\n            </dd>\n          </dl>\n        </div>\n      ",
    "\n      <div id=\"search\">\n        <dl id=\"searchbox\">\n        <dt>Search</dt>\n        <dd>\n        <form action=\"/search\" method=\"get\">\n        <fieldset>\n        <input class=\"search-input\" type=\"text\" onclick=\"this.select()\" value=\"Search this shop...\" name=\"q\" />\n        </fieldset>\n        </form>\n        </dd>\n        </dl>\n      </div>\n      <div id=\"navigation\">\n        <dl class=\"navbar\">\n        <dt>Navigation</dt>\n        ",
    "\n          <dd>",
    "</dd>\n        ",
    "\n        </dl>\n\n        ",
    "\n        <dl class=\"navbar\">\n        <dt>Tags</dt>\n          ",
    "</dd>\n          ",
    "\n          </dl>\n        ",
    "\n      </div>\n    </div>\n\n  </div>\n    <div id=\"content-padding\"></div>\n</div>\n\n<div id=\"footer\">\n  ",
    "\n</div>\n\n</body>\n</html>\n",
    "<div id=\"blog-page\">\n  <h2 class=\"heading-shaded\">",
    "</h2>\n   ",
    "\n      <h4>\n        ",
    "</a>\n      </h4>\n      ",
    "\n        <p><a href=\"",
    "\n</div>\n",
    "<script type=\"text/javascript\">\n  function remove_item(id) {\n      document.getElementById('updates_'+id).value = 0;\n      document.getElementById('cart').submit();\n  }\n</script>\n\n<div id=\"cart-page\">\n\n  ",
    "\n    <p>Your shopping cart is empty...</p>\n  <p><a href=\"/\"><img src=\"",
    "\" alt=\"Continue shopping\"/></a><p>\n  ",
    "\n\n  <form action=\"/cart\" method=\"post\" id=\"cart\">\n\n  <table class=\"cart\">\n      <tr>\n        <th colspan=\"2\">Product</th>\n        <th class=\"short\">Qty</th>\n        <th>Price</th>\n        <th>Total</th>\n        <th class=\"short\">Remove</th>\n      </tr>\n\n      ",
    "\n      <tr class=\"",
    "\">\n        <td class=\"short\">",
    "</td>\n    <td><a href=\"",
    "</a></td>\n        <td class=\"short\"><input type=\"text\" class=\"quantity\" name=\"updates[",
    "\" onfocus=\"this.select();\"/></td>\n        <td class=\"cart-price\">",
    "</td>\n        <td class=\"cart-price\">",
    "</td>\n        <td class=\"short\"><a href=\"#\" onclick=\"remove_item(",
    "); return false;\" class=\"remove\"><img src=\"",
    "\" alt=\"Remove\" /></a></td>\n      </tr>\n      ",
    "\n    </table>\n    <p class=\"updatebtn\"><input type=\"image\" value=\"Update Cart\" name=\"update\" src=\"",
    "\" alt=\"Update\" /></p>\n    <p class=\"subtotal\">\n    <strong>Subtotal:</strong> ",
    "\n    </p>\n    <p class=\"checkout\"><input type=\"image\" src=\"",
    "\" alt=\"Proceed to Checkout\" value=\"Proceed to Checkout\" name=\"checkout\"  /></p>\n\n    ",
    "<div id=\"collection-page\">\n\n",
    "\n  <div id=\"collection-description\" class=\"textile\">",
    "\n    <li class=\"single-product clearfix\">\n      <div class=\"small\">\n        <div class=\"prod-image\"><a href=\"",
    "\" /></a></div>\n      </div>\n      <div class=\"prod-list-description\">\n        <h3><a href=\"",
    "</p>\n      <p class=\"prd-price\">",
    "<div id=\"home-page\">\n  <h3 class=\"heading-shaded\">Featured products...</h3>\n  <div class=\"featured-prod-row clearfix\">\n    ",
    "\n      <div class=\"featured-prod-item\">\n          <p>\n        <a href=\"",
    "\"/></a>\n        </p>\n        <h4><a href=\"",
    "</a></h4>\n        ",
    "\n          ",
    "\n            <p class=\"prd-price\">Was:<del>",
    "</del></p>\n            <p class=\"prd-price\"><ins>Now: ",
    "</ins></p>\n          ",
    "\n          <p class=\"prd-price\"><ins>",
    "</ins></p>\n        ",
    "\n      </div>\n    ",
    "\n  </div>\n\n  <div id=\"articles\">\n    ",
    "\n      <h3>",
    "</h3>\n      ",
    "\n      In <em>Admin &gt; Blogs &amp; Pages</em>, create a page with the handle <strong><code>frontpage</code></strong> and it will show up here.<br />\n      ",
    "\n  </div>\n</div>\n",
    "<div id=\"single-page\">\n<h2 class=\"heading-shaded\">",
    "</h2>\n  ",
    "<div id=\"product-page\">\n  <h2 class=\"heading-shaded\">",
    "</h2>\n  <div id=\"product-details\">\n  <div id=\"product-images\">\n    ",
    "\" class=\"product-image\" rel=\"lightbox[ product]\" title=\"\">\n          <img src=\"",
    "\" class=\"product-image-small\" rel=\"lightbox[ product]\" title=\"\">\n          <img src=\"",
    "\n  </div>\n\n  <ul id=\"product-info\">\n    <li>Vendor: ",
    "</li>\n    </ul>\n\n    <small>",
    "</small>\n\n    <div id=\"product-options\">\n              ",
    "\n\n    <form action=\"/cart/add\" method=\"post\">\n\n      <select id=\"product-select\" name='id'>\n        ",
    "\n      </select>\n\n      <div id=\"price-field\"></div>\n\n      <div class=\"add-to-cart\"><input type=\"image\" name=\"add\" value=\"Add to Cart\" id=\"add\" src=\"",
    "\" /></div>\n    </form>\n              ",
    "\n                  <span>Sold Out!</span>\n              ",
    "\n    </div>\n\n    <div class=\"product-description\">\n    ",
    "\n    </div>\n  </div>\n</div>\n\n\n<script type=\"text/javascript\">\n<!--\n  // mootools callback for multi variants dropdown selector\n  var selectCallback = function(variant, selector) {\n    if (variant && variant.available == true) {\n      // selected a valid variant\n      $('add').removeClass('disabled'); // remove unavailable class from add-to-cart button\n      $('add').disabled = false;           // reenable add-to-cart button\n      $('price-field').innerHTML = Shopify.formatMoney(variant.price, \"",
    "\");  // update price field\n    } else {\n      // variant doesn't exist\n      $('add').addClass('disabled');      // set add-to-cart button to unavailable class\n      $('add').disabled = true;              // disable add-to-cart button\n      $('price-field').innerHTML = (variant) ? \"Sold Out\" : \"Unavailable\"; // update price-field message\n    }\n  };\n\n  // initialize multi selector for product\n  window.addEvent('domready', function() {\n    new Shopify.OptionSelectors(\"product-select\", { product: ",
    ", onVariantSelected: selectCallback });\n  });\n-->\n</script>\n\n",
    "  <div id=\"page\" class=\"innerpage clearfix\">\n\n    <div id=\"text-page\">\n      <div class=\"entry\">\n        <h1>Oh no!</h1>\n        <div class=\"entry-post\">\n          Seems like you are looking for something that just isn't here. <a href=\"/\">Try heading back to our main page</a>. Or you can checkout some of our featured products below.\n        </div>\n      </div>\n    </div>\n\n\n    <h1>Featured Products</h1>\n    <ul class=\"item-list clearfix\">\n\n      ",
    "\n      <li>\n        <form action=\"/cart/add\" method=\"post\">\n        <div class=\"item-list-item\">\n          <div class=\"ili-top clearfix\">\n            <div class=\"ili-top-content\">\n              <h2><a href=\"",
    "</a></h2>\n              <p>",
    "</p>\n            </div>\n            <a href=\"",
    "\" class=\"ili-top-image\"><img src=\"",
    "\"/></a>\n          </div>\n\n          <div class=\"ili-bottom clearfix\">\n            <p class=\"hiddenvariants\" style=\"display: none\">",
    "<span><input type=\"radio\" name=\"id\" value=\"",
    "\" id=\"radio_",
    "\" style=\"vertical-align: middle;\" ",
    " checked=\"checked\" ",
    " /><label for=\"radio_",
    "</label></span>",
    "</p>\n            <input type=\"submit\" class=\"\" value=\"Add to Basket\" />\n            <p>\n              <a href=\"",
    "\">View Details</a>\n\n              <span>\n                ",
    "\n                  ",
    "\n                    ",
    " -\n                    ",
    "\n                ",
    "\n                <strong>\n                  ",
    "\n                </strong>\n              </span>\n            </p>\n          </div>\n        </div>\n        </form>\n      </li>\n      ",
    "\n\n    </ul>\n  </div>\n  <!-- end page -->\n\n\n\n",
    "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n<html xmlns=\"http://www.w3.org/1999/xhtml\">\n<head>\n  <title>",
    "</title>\n  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"/>\n\n  ",
    "\n</head>\n<body id=\"page-",
    "\">\n\n<div id=\"wrap\">\n\n  <div id=\"top\">\n    <div id=\"cart\">\n      <h3>Shopping Cart</h3>\n      <p class=\"cart-count\">\n        ",
    "\n          Your cart is currently empty\n        ",
    " <span>-</span> Total: ",
    " <span>-</span> <a href=\"/cart\">View Cart</a>\n        ",
    "\n      </p>\n    </div>\n\n    <div id=\"site-title\">\n      <h3><a href=\"/\">",
    "</a></h3>\n      <h4><span>Tribble: A Shopify Theme</span></h4>\n\n    </div>\n  </div>\n\n  <ul id=\"nav\">\n    ",
    "\n     <li>",
    "</li>\n    ",
    "\n  </ul>\n\n  ",
    "\n\n  <div id=\"foot\" class=\"clearfix\">\n    <div class=\"quick-links\">\n      <h4>Quick Navigation</h4>\n      <ul class=\"clearfix\">\n        <li><a href=\"/\">Home</a></li>\n        <li><a href=\"#top\">Back to top</a></li>\n        ",
    "\n         <li>",
    "\n      </ul>\n    </div>\n\n    <div class=\"quick-contact\">\n      <h4>Quick Contact</h4>\n      <div class=\"vcard\">\n\n          <div class=\"org fn\">\n             <div class=\"organization-name\">Really Great Widget Co.</div>\n          </div>\n        <div class=\"adr\">\n            <span class=\"street-address\">2531 Barrington Court</span>\n            <span class=\"locality\">Hayward</span>,\n          <abbr title=\"California\" class=\"region\">CA</abbr>\n            <span class=\"postal-code\">94545</span>\n         </div>\n        <a class=\"email\" href=\"mailto:email@myshopifysite.com\">\n          email@myshopifysite.com\n        </a>\n        <div class=\"tel\">\n          <span class=\"type\">Support:</span> <span class=\"value\">800-555-9954</span>\n        </div>\n      </div>\n\n    </div>\n\n    <p><a href=\"http://shopify.com\" class=\"we-made\">Powered by Shopify</a> &copy; Copyright ",
    ", All Rights Reserved.  <a href=\"/blogs/news.xml\" id=\"foot-rss\">RSS Feed</a></p>\n  </div>\n\n</div>\n\n</body>\n</html>\n",
    "\n  <div id=\"page\" class=\"innerpage clearfix\">\n    <div id=\"text-page\">\n\n          <div class=\"entry\">\n            <h1><span>",
    "</span></h1>\n            <div class=\"entry-post\">\n              <div class=\"meta\">",
    "</div>\n              ",
    "\n            </div>\n\n  <!-- Comments -->\n",
    "\n<div id=\"comments\">\n  <h2>Comments</h2>\n\n  <!-- List all comments -->\n  <ul id=\"comment-list\">\n  ",
    "\n      </div>\n\n      <div class=\"comment-details\">\n        Posted by <span class=\"comment-author\">",
    "</span> on <span class=\"comment-date\">",
    "</span>\n      </div>\n    </li>\n  ",
    "\n    <h2>Leave a comment</h2>\n\n    <!-- Check if a comment has been submitted in the last request, and if yes display an appropriate message -->\n    ",
    "\n<!-- END Comments -->\n\n\n          </div>\n    </div>\n\n    <div id=\"three-reasons\" class=\"clearfix\">\n      <h3>Why Shop With Us?</h3>\n      <ul>\n        <li class=\"two-a\">\n          <h4>24 Hours</h4>\n          <p>We're always here to help.</p>\n        </li>\n        <li class=\"two-c\">\n          <h4>No Spam</h4>\n          <p>We'll never share your info.</p>\n        </li>\n        <li class=\"two-d\">\n          <h4>Secure Servers</h4>\n          <p>Checkout is 256bit encrypted.</p>\n        </li>\n      </ul>\n    </div>\n  </div>\n",
    "  <div id=\"page\" class=\"innerpage clearfix\">\n    <div id=\"text-page\">\n      <h1>Post from our blog...</h1>\n      ",
    "\n\n          <div class=\"entry\">\n            <h1><span><a href=\"",
    "</a></span></h1>\n            <div class=\"entry-post\">\n              <div class=\"meta\">",
    "\n            </div>\n          </div>\n\n        ",
    "\n\n        <div class=\"paginate clearfix\">\n            ",
    "\n        </div>\n\n      ",
    "\n    </div>\n\n    <div id=\"three-reasons\" class=\"clearfix\">\n      <h3>Why Shop With Us?</h3>\n      <ul>\n        <li class=\"two-a\">\n          <h4>24 Hours</h4>\n          <p>We're always here to help.</p>\n        </li>\n        <li class=\"two-c\">\n          <h4>No Spam</h4>\n          <p>We'll never share your info.</p>\n        </li>\n        <li class=\"two-d\">\n          <h4>Secure Servers</h4>\n          <p>Checkout is 256bit encrypted.</p>\n        </li>\n      </ul>\n    </div>\n  </div>\n",
    "<script type=\"text/javascript\">\n  function remove_item(id) {\n      document.getElementById('updates_'+id).value = 0;\n      document.getElementById('cart').submit();\n  }\n</script>\n\n  <div id=\"page\" class=\"innerpage clearfix\">.\n    ",
    "\n         <h1>Your cart is currently empty.</h1>\n      ",
    "\n\n    <h1>Your Cart <span>(",
    " total)</span></h1>\n\n    <form action=\"/cart\" method=\"post\" id=\"cart-form\">\n\n    <div id=\"cart-wrap\">\n      <table width=\"100%\" border=\"0\" cellspacing=\"0\" cellpadding=\"0\">\n        <tr>\n          <th scope=\"col\" class=\"td-image\"><label>Image</label></th>\n          <th scope=\"col\" class=\"td-title\"><label>Product Title</label></th>\n          <th scope=\"col\" class=\"td-count\"><label>Count</label></th>\n          <th scope=\"col\" class=\"td-price\"><label>Cost</label></th>\n          <th scope=\"col\" class=\"td-delete\"><label>Remove</label></th>\n        </tr>\n\n        ",
    "\n        <tr class=\"",
    "\">\n          <td colspan=\"5\">\n            <table width=\"100%\" border=\"0\" cellspacing=\"0\" cellpadding=\"0\">\n              <tr>\n                <td class=\"td-image\"><a href=\"",
    "</a></td>\n                <td class=\"td-title\"><p>",
    "</p></td>\n                <td class=\"td-count\"><label>Count:</label> <input type=\"text\" class=\"quantity item-count\" name=\"updates[",
    "\" onfocus=\"this.select();\"/></td>\n                <td class=\"td-price\">",
    "</td>\n                <td class=\"td-delete\"><a href=\"#\" onclick=\"remove_item(",
    "); return false;\">Remove</a></td>\n              </tr>\n            </table>\n          </td>\n        </tr>\n        ",
    "\n      </table>\n\n      <div id=\"finish-up\">\n\n        <div class=\"latest-news-box\">\n          ",
    "\n        </div>\n\n        <p class=\"order-total\">\n          <span><strong>Order Total:</strong> ",
    "</span>\n        </p>\n\n        <p class=\"update-cart\"><input type=\"submit\" value=\"Refresh Cart\" name=\"update\" /></p>\n\n          <p class=\"go-checkout\"><input type=\"submit\" value=\"Proceed to Checkout\" name=\"checkout\"  /></p>\n\n        ",
    "\n        <div class=\"additional-checkout-buttons\">\n          <p>- or -</p>\n          ",
    "\n        </div>\n        ",
    "\n\n      </div>\n\n    </div>\n\n    </form>\n\n    ",
    "\n\n\n\n    <h1 class=\"other-products\"><span>Other Products You Might Enjoy</span></h1>\n    <ul class=\"item-list clearfix\">\n\n      ",
    "\n\n    </ul>\n\n    <div id=\"three-reasons\" class=\"clearfix\">\n      <h3>Why Shop With Us?</h3>\n      <ul>\n        <li class=\"two-a\">\n          <h4>24 Hours</h4>\n          <p>We're always here to help.</p>\n        </li>\n        <li class=\"two-c\">\n          <h4>No Spam</h4>\n          <p>We'll never share your info.</p>\n        </li>\n        <li class=\"two-d\">\n          <h4>Secure Servers</h4>\n          <p>Checkout is 256bit encrypted.</p>\n        </li>\n      </ul>\n    </div>\n\n  </div>\n  <!-- end page -->\n",
    "  <div id=\"page\" class=\"innerpage clearfix\">\n    <h1>",
    "</h1>\n    ",
    "\n      <div class=\"latest-news\">",
    "</div>\n    ",
    "\n\n    <ul class=\"item-list clearfix\">\n    ",
    "\n                </strong>\n              </span>\n            </p>\n          </div>\n        </div>\n        </form>\n      </li>\n    ",
    "\n    </ul>\n\n    <div class=\"paginate clearfix\">\n      ",
    "\n    </div>\n\n\n    <div id=\"three-reasons\" class=\"clearfix\">\n      <h3>Why Shop With Us?</h3>\n      <ul>\n        <li class=\"two-a\">\n          <h4>24 Hours</h4>\n          <p>We're always here to help.</p>\n        </li>\n        <li class=\"two-c\">\n          <h4>No Spam</h4>\n          <p>We'll never share your info.</p>\n        </li>\n        <li class=\"two-d\">\n          <h4>Secure Servers</h4>\n          <p>Checkout is 256bit encrypted.</p>\n        </li>\n      </ul>\n    </div>\n  </div>\n\n",
    "  <div id=\"gwrap\">\n    <div id=\"gbox\">\n      <h1>Three Great Reasons You Should Shop With Us...</h1>\n      <ul>\n        <li class=\"gbox1\">\n          <h2>Free Shipping</h2>\n          <p>On all orders over $25</p>\n        </li>\n        <li class=\"gbox2\">\n          <h2>Top Quality</h2>\n          <p>Hand made in our shop</p>\n        </li>\n        <li class=\"gbox3\">\n          <h2>100% Guarantee</h2>\n          <p>Any time, any reason</p>\n        </li>\n      </ul>\n    </div>\n  </div>\n\n  <div id=\"page\" class=\"clearfix\">\n\n    <div class=\"latest-news\">",
    "</div>\n\n    <ul class=\"item-list clearfix\">\n\n      ",
    "</a></h2>\n              ",
    "</p> <!-- extra cloding <p> tag for truncation -->\n            </div>\n            <a href=\"",
    "\n\n    </ul>\n\n    <div id=\"one-two\">\n      <div id=\"two\">\n        <h3>Why Shop With Us?</h3>\n        <ul>\n          <li class=\"two-a\">\n            <h4>24 Hours</h4>\n            <p>We're always here to help.</p>\n          </li>\n          <li class=\"two-c\">\n            <h4>No Spam</h4>\n            <p>We'll never share your info.</p>\n          </li>\n          <li class=\"two-b\">\n            <h4>Save Energy</h4>\n            <p>We're green, all the way.</p>\n          </li>\n          <li class=\"two-d\">\n            <h4>Secure Servers</h4>\n            <p>Checkout is 256bits encrypted.</p>\n          </li>\n        </ul>\n      </div>\n\n      <div id=\"one\">\n        <h3>Our Company</h3>\n        ",
    " <a href=\"/pages/about-us\">read more</a></p>\n      </div>\n    </div>\n\n  </div>\n  <!-- end page -->\n",
    "  <div id=\"page\" class=\"innerpage clearfix\">\n\n    <div id=\"text-page\">\n      <div class=\"entry\">\n        <h1>",
    "</h1>\n        <div class=\"entry-post\">\n          ",
    "\n        </div>\n      </div>\n    </div>\n\n\n    <h1>Featured Products</h1>\n    <ul class=\"item-list clearfix\">\n\n      ",
    "<div id=\"page\" class=\"innerpage clearfix\">\n  <h1>",
    "</h1>\n\n\n  <p class=\"latest-news\"><strong>Product Tags: </strong>\n    ",
    "\n            <a href=\"/collections/all/",
    "</a> |\n          ",
    "\n  </p>\n\n  <div class=\"product clearfix\">\n    <div class=\"product-info\">\n      <h1>",
    "</h1>\n      <div class=\"product-info-description\">\n        <p>",
    "  </p>\n      </div>\n\n      ",
    "\n      <form action=\"/cart/add\" method=\"post\">\n\n      <h2>Product Options:</h2>\n\n      <select id=\"product-info-options\" name=\"id\" class=\"product-info-options\">\n        ",
    "\n      </select>\n\n      <div id=\"price-field\"></div>\n\n      <div class=\"product-purchase-btn\">\n        <input type=\"submit\" class=\"add-this-to-cart\" id=\"add-this-to-cart\" value=\"Add to Basket\" />\n      </div>\n\n      </form>\n      ",
    "\n              <h2>Sold out!</h2>\n              <p>Sorry, we're all out of this product. Check back often and order when it returns</p>\n              ",
    "\n    </div>\n\n    <div class=\"product-images clearfix\">\n      ",
    "\n\n      ",
    "\n      <div class=\"product-image-large\">\n        <img src=\"",
    "\" />\n      </div>\n      ",
    "\n\n      <ul class=\"product-thumbs clearfix\">\n      ",
    "\n\n      <li>\n      <a href=\"",
    "\" class=\"product-thumbs\" rel=\"lightbox[product]\" title=\"\">\n        <img src=\"",
    "\" />\n      </a>\n      </li>\n      ",
    "\n      </ul>\n    </div>\n  </div>\n\n\n\n  <div id=\"three-reasons\" class=\"clearfix\">\n    <h3>Why Shop With Us?</h3>\n    <ul>\n      <li class=\"two-a\">\n        <h4>24 Hours</h4>\n        <p>We're always here to help.</p>\n      </li>\n      <li class=\"two-c\">\n        <h4>No Spam</h4>\n        <p>We'll never share your info.</p>\n      </li>\n      <li class=\"two-d\">\n        <h4>Secure Servers</h4>\n        <p>Checkout is 256bit encrypted.</p>\n      </li>\n    </ul>\n  </div>\n\n</div>\n<!-- end page -->\n\n<script type=\"text/javascript\">\n<!--\n  // prototype callback for multi variants dropdown selector\n  var selectCallback = function(variant, selector) {\n    if (variant && variant.available == true) {\n      // selected a valid variant\n      $('add-this-to-cart').removeClassName('disabled'); // remove unavailable class from add-to-cart button\n      $('add-this-to-cart').disabled = false;           // reenable add-to-cart button\n      $('price-field').innerHTML = Shopify.formatMoney(variant.price, \"",
    "\");  // update price field\n    } else {\n      // variant doesn't exist\n      $('add-this-to-cart').addClassName('disabled');      // set add-to-cart button to unavailable class\n      $('add-this-to-cart').disabled = true;              // disable add-to-cart button\n      $('price-field').innerHTML = (variant) ? \"Sold Out\" : \"Unavailable\"; // update price-field message\n    }\n  };\n\n  // initialize multi selector for product\n  Event.observe(document, 'dom:loaded', function() {\n    new Shopify.OptionSelectors(\"product-info-options\", { product: ",
    ", onVariantSelected: selectCallback });\n  });\n-->\n</script>\n\n\n",
    "\n\n\n\n    <div id=\"page\" class=\"innerpage clearfix\">\n    <h1>Search Results</h1>\n    ",
    "\n      <div class=\"latest-news\">Your search for \"",
    "\" did not yield any results</div>\n        ",
    "\n\n\n    <ul class=\"search-list clearfix\">\n     ",
    "\n      <li>\n          <h3 class=\"stitle\">",
    "</h3>\n          <p class=\"sinfo\">",
    " ... <a href=\"",
    "\" title=\"\">view this item</a></p>\n      </li>\n    ",
    "\n    </ul>\n     ",
    "\n\n    <div class=\"paginate clearfix\">\n      ",
    "<div class=\"article\">\n  <h3 class=\"article-head-title\">",
    "</h3>\n  <p> posted ",
    "</p>\n  <div class=\"article-body textile\">\n    ",
    "\n  </div>\n</div>\n\n",
    "\n<div id=\"comments\">\n  <h3>Comments</h3>\n  <!-- List all comments -->\n\n  <ul>\n  ",
    "\n  </ul>\n\n  <!-- Comment Form -->\n  ",
    "\n\n    <input type=\"submit\" value=\"Post comment\" />\n  ",
    "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n<html xmlns=\"http://www.w3.org/1999/xhtml\">\n\n<head>\n<title>",
    " &mdash; ",
    "</title>\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n\n",
    "\n\n<!-- Additional colour schemes for this theme. If you want to use them, just replace the above line with one of these\n",
    "\">\n\n<div id=\"header\">\n  <div class=\"container\">\n    <div id=\"logo\">\n      <h1><a href=\"/\" title=\"",
    "</a></h1>\n    </div>\n    <div id=\"navigation\">\n      <ul id=\"navigate\">\n        <li><a href=\"/cart\">View Cart</a></li>\n        ",
    "\n          <li><a href=\"",
    "</a></li>\n        ",
    "\n      </ul>\n    </div>\n  </div>\n</div>\n\n<div id=\"mini-header\">\n  <div class=\"container\">\n    <div id=\"shopping-cart\">\n      <a href=\"/cart\">Your shopping cart contains ",
    "</a>\n    </div>\n    <div id=\"search-box\">\n      <form action=\"/search\" method=\"get\">\n        <input type=\"text\" name=\"q\" id=\"q\" />\n        <input type=\"image\" src=\"",
    "\" value=\"Seek\" onclick=\"this.parentNode.submit(); return false;\" id=\"seek\" />\n      </form>\n    </div>\n  </div>\n</div>\n\n<div id=\"layout\">\n  <div class=\"container\">\n    <div id=\"layout-left\" ",
    "style=\"width:619px\"",
    "\n      <h1>Search Results</h1>",
    "\n    </div>",
    "\n\n    <div id=\"layout-right\">\n      ",
    "\n      <a href=\"",
    "/blogs/news.xml\"><img src=\"",
    "\" alt=\"Subscribe\" class=\"feed\" /></a>\n      <h3><a href=\"/blogs/news\">More news</a></h3>\n      <ul id=\"blogs\">",
    "\n        <li><a href=\"",
    "</a><br />\n          <small>",
    "</small>\n        </li>",
    "\n      </ul>\n      ",
    "\n      <h3>Collection Tags</h3>\n      <div id=\"tags\">",
    "\n        No tags found.",
    "\n        <span class=\"tags\">",
    "\n      </div>\n      ",
    "\n\n      <h3>Navigation</h3>\n      <ul id=\"links\">\n      ",
    "</a></li>\n      ",
    "\n      </ul>\n\n      ",
    "\n      <h3>Featured Products</h3>\n      <ul id=\"featuring\">",
    "\n        <li class=\"featuring-list\">\n          <div class=\"featuring-image\">\n            <a href=\"",
    "\" title=\"",
    "\" /></a>\n          </div>\n          <div class=\"featuring-info\">\n            <a href=\"",
    "</a><br />\n            <small><span class=\"light\">from</span> ",
    "</small>\n          </div>\n        </li>",
    "\n  </div>\n</div>\n\n<div id=\"footer\">\n  <div id=\"footer-fader\">\n    <div class=\"container\">\n      <div id=\"footer-right\">",
    "\n      </div>\n      <span id=\"footer-left\">\n        Copyright &copy; ",
    " <a href=\"/\">",
    "</a>. All Rights Reserved. All prices ",
    ".<br />\n        This website is powered by <a href=\"http://www.shopify.com\">Shopify</a>.\n      </span>\n    </div>\n  </div>\n</div>\n\n</body>\n</html>\n",
    "<div id=\"shop-id-label_about\">\n<h3 class=\"article-head-title\">",
    "\n    <div class=\"article\">\n      <h3 class=\"article-head-title\">\n        <a href=\"",
    "</a>\n      </h3>\n\n      <p>\n      ",
    " comments</a>\n        &mdash;\n      ",
    "\n      posted ",
    "</p>\n      <div class=\"article-body textile\">\n        ",
    "\n      </div>\n    </div>\n  ",
    "\n\n  <div id=\"pagination\">\n    ",
    "\n  </div>\n\n",
    "\n\n\n</div>\n<div class=\"clear-me\"></div>\n",
    "<h1>Shopping Cart</h1>\n",
    "\n  <p><strong>Your shopping basket is empty.</strong> Perhaps a featured item below is of interest...</p>\n  <table id=\"gallery\">\n  ",
    "\n    <div class=\"gallery-image\">\n      <a href=\"",
    "\" /></a>\n    </div>\n    <div class=\"gallery-info\">\n      <a href=\"",
    "</a><br />\n      <small>",
    "</small>\n    </div>\n  ",
    "\n  </table>\n",
    "\n<script type=\"text/javascript\">\n  function remove_item(id) {\n      document.getElementById('updates_'+id).value = 0;\n      document.getElementById('cartform').submit();\n  }\n</script>\n<form action=\"/cart\" method=\"post\" id=\"cartform\">\n  <table id=\"basket\">\n    <tr>\n      <th>Item Description</th>\n      <th>Price</th>\n      <th>Qty</th>\n      <th>Delete</th>\n      <th>Total</th>\n    </tr>",
    "\n    <tr class=\"basket-",
    "\">\n      <td class=\"basket-column-one\">\n        <div class=\"basket-images\">\n          <a href=\"",
    "\" /></a>\n        </div>\n        <div class=\"basket-desc\">\n          <p><a href=\"",
    "</a></p>\n          ",
    "\n        </div>\n      </td>\n      <td class=\"basket-column\">",
    "<br /><del>",
    "</td>\n      <td class=\"basket-column\"><input type=\"text\" size=\"4\" name=\"updates[",
    "\" onfocus=\"this.select();\"/></td>\n      <td class=\"basket-column\"><a href=\"#\" onclick=\"remove_item(",
    "); return false;\">Remove</a></td>\n      <td class=\"basket-column\">",
    "</td>\n    </tr>",
    "\n  </table>\n  <div id=\"basket-right\">\n    <h3>Subtotal ",
    "</h3>\n    <input type=\"image\" src=\"",
    "\" id=\"update-cart\" name=\"update\" value=\"Update\" />\n    <input type=\"image\" src=\"",
    "\" name=\"checkout\" value=\"Checkout\" />\n    ",
    "\n  </div>\n</form>",
    "\n  <strong>No products found in this collection.</strong>",
    "</h1>\n  ",
    "\n  <table id=\"gallery\">\n  ",
    "\n  </table>",
    "\n  <div id=\"paginate\">\n    ",
    "\n  </div>",
    "  <div id=\"about-excerpt\">\n    ",
    "\n      <h2>",
    "</h2>\n      ",
    "\n  </div>\n\n  <table id=\"gallery\">\n  ",
    "<div id=\"product-left\">\n  ",
    "<div id=\"product-image\">\n    <a href=\"",
    "\" rel=\"lightbox[images]\" title=\"",
    "\" /></a>\n  </div>",
    "\n  <div class=\"product-images\">\n    <a href=\"",
    "\n</div>\n<div id=\"product-right\">\n  <h1>",
    "\n  <form action=\"/cart/add\" method=\"post\">\n\n    <div id=\"product-variants\">\n      <div id=\"price-field\"></div>\n\n      <select id=\"product-select\" name='id'>\n        ",
    "\n      </select>\n    </div>\n\n    <input type=\"image\" src=\"",
    "\" name=\"add\" value=\"Purchase\" id=\"purchase\" />\n  </form>\n  ",
    "\n    <p class=\"bold-red\">This product is temporarily unavailable</p>\n  ",
    "\n\n  <div id=\"product-details\">\n    <strong>Continue Shopping</strong><br />\n    Browse more ",
    " or additional ",
    " products.\n  </div>\n</div>\n\n\n<script type=\"text/javascript\">\n<!--\n  // mootools callback for multi variants dropdown selector\n  var selectCallback = function(variant, selector) {\n    if (variant && variant.available == true) {\n      // selected a valid variant\n      $('purchase').removeClass('disabled'); // remove unavailable class from add-to-cart button\n      $('purchase').disabled = false;           // reenable add-to-cart button\n      $('price-field').innerHTML = Shopify.formatMoney(variant.price, \"",
    "\");  // update price field\n    } else {\n      // variant doesn't exist\n      $('purchase').addClass('disabled');      // set add-to-cart button to unavailable class\n      $('purchase').disabled = true;              // disable add-to-cart button\n      $('price-field').innerHTML = (variant) ? \"Sold Out\" : \"Unavailable\"; // update price-field message\n    }\n  };\n\n  // initialize multi selector for product\n  window.addEvent('domready', function() {\n    new Shopify.OptionSelectors(\"product-select\", { product: ",
  ].each do |_seg|
    _lh = _seg.bytesize
    _ln = _seg.bytesize < 28 ? _seg.bytesize : 28
    _ln.times { |_i| _lh = (((_lh << 5) + _lh) ^ _seg.getbyte(_i)) & 0xFFFFFFFF }
    Liquid::Tokenizer::FROZEN_LONG_TEXT_TABLE[_lh] = _seg.freeze
  end
  Liquid::Tokenizer::FROZEN_LONG_TEXT_TABLE.freeze
end
