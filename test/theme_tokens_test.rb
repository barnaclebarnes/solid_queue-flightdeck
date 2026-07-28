# frozen_string_literal: true

require "test_helper"

# Guards the theme token chain.
#
# The failure this prevents is specific and was reported from browser QA: with
# the OS in dark mode and an explicit light stamp, part of the UI stayed dark.
# That happens when one of the four theme selector blocks is missing a token the
# others define, so that token keeps its inherited value. These tests assert the
# blocks stay in step, and that every colour a component uses comes from a token
# rather than being written into the component rule.
class Flightdeck::ThemeTokensTest < ActiveSupport::TestCase
  SOURCE = Pathname.new(File.expand_path("../assets-src/input.css", __dir__))

  setup do
    @css = SOURCE.read
  end

  test "each palette is defined exactly once and covers the same tokens" do
    light = palette("light")
    dark = palette("dark")

    assert_operator light.size, :>=, 20, "the light palette looks suspiciously small"
    assert_equal light, dark, "the light and dark palettes must cover the same token names"
  end

  test "all four selector blocks map exactly the same tokens" do
    blocks = {
      ":root (default)" => mapped(/^:root \{\n  color-scheme: light;\n(.*?)^\}/m),
      "@media dark" => mapped(/:root:where\(:not\(\[data-theme="light"\]\)\) \{\n    color-scheme: dark;\n(.*?)^  \}/m),
      '[data-theme="dark"]' => mapped(/^:root\[data-theme="dark"\] \{\n  color-scheme: dark;\n(.*?)^\}/m),
      '[data-theme="light"]' => mapped(/^:root\[data-theme="light"\] \{\n  color-scheme: light;\n(.*?)^\}/m)
    }

    blocks.each { |name, tokens| assert_operator tokens.size, :>=, 20, "#{name} defines almost nothing" }

    reference = blocks[":root (default)"]
    blocks.each do |name, tokens|
      assert_equal reference, tokens,
                   "#{name} does not define the same tokens as :root — " \
                   "the missing ones would keep their inherited value when that block wins"
    end
  end

  test "every selector block only maps tokens to palette entries" do
    %w[light dark].each do |theme|
      references = @css.scan(/var\(--fd-#{theme}-([a-z0-9-]+)\)/).flatten.uniq.sort

      assert_equal palette(theme), references,
                   "every #{theme} palette entry should be referenced exactly by the mapping blocks"
    end
  end

  test "no var() refers to a palette entry that does not exist" do
    referenced = @css.scan(/var\((--fd-[a-z0-9-]+)\)/).flatten.uniq
    defined = @css.scan(/^\s*(--fd-[a-z0-9-]+):/).flatten.uniq

    assert_empty referenced - defined, "these palette entries are referenced but never defined"
  end

  test "the light stamp beats the OS dark preference by specificity" do
    assert_match(/:root:where\(:not\(\[data-theme="light"\]\)\)/, @css,
                 "the media block must be guarded so an explicit light stamp wins")
  end

  test "shell components take their colours from tokens, never from literals" do
    shell = %w[.fd-side .fd-topbar .fd-app .fd-nav-link .fd-brand-word .fd-side-foot .fd-main]

    shell.each do |selector|
      body = rule_body(selector)
      next if body.nil?

      body.scan(/^\s*[a-z-]+\s*:\s*([^;]+);/).flatten.each do |value|
        # Only opaque literal colours matter: a translucent overlay reads
        # correctly over either palette, and lengths are not colours at all.
        literal = value[/#[0-9a-fA-F]{3,8}\b/] || value[/\brgb\([^)]*\)/]
        next if literal.nil?

        flunk "#{selector} uses the literal colour #{literal}; it will not follow the theme"
      end
    end
  end

  private
    def palette(theme)
      @css.scan(/^  --fd-#{theme}-([a-z0-9-]+):/).flatten.sort
    end

    def mapped(pattern)
      body = @css[pattern, 1]
      assert_not_nil body, "could not find the theme block matching #{pattern.inspect}"
      body.scan(/^\s*(--[a-z0-9-]+):/).flatten.sort
    end

    def rule_body(selector)
      @css[/^#{Regexp.escape(selector)} \{\n(.*?)^\}/m, 1]
    end
end
