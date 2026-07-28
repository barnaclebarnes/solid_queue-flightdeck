# frozen_string_literal: true

require "test_helper"

class Flightdeck::AssetsTest < ActionDispatch::IntegrationTest
  test "serves a digested stylesheet as an immutable asset" do
    name = Flightdeck::Assets.digested_name("flightdeck.css")
    get "/flightdeck/assets/#{name}"

    assert_response :success
    assert_equal "text/css", response.media_type
    assert_equal %w[immutable max-age=31536000 public], response.headers["Cache-Control"].split(", ").sort
    assert_equal %("#{name[/flightdeck-([0-9a-f]{12})/, 1]}"), response.headers["ETag"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.body, ".fd-app"
  end

  test "serves a digested script as an immutable asset" do
    name = Flightdeck::Assets.digested_name("flightdeck.js")
    get "/flightdeck/assets/#{name}"

    assert_response :success
    assert_equal "text/javascript", response.media_type
    assert_equal %w[immutable max-age=31536000 public], response.headers["Cache-Control"].split(", ").sort
    assert_includes response.body, "Stimulus"
  end

  test "returns 304 when the client already has the digest" do
    name = Flightdeck::Assets.digested_name("flightdeck.css")
    get "/flightdeck/assets/#{name}"
    etag = response.headers["ETag"]

    get "/flightdeck/assets/#{name}", headers: { "HTTP_IF_NONE_MATCH" => etag }

    assert_response :not_modified
  end

  test "a well-formed but unknown digest is not served" do
    get "/flightdeck/assets/flightdeck-000000000000.css"

    assert_response :not_found
  end

  test "names that are not digested asset names do not route" do
    [
      "flightdeck.css",
      "../../../etc/passwd",
      "flightdeck-6f7ad8f56f16.css/../../secret",
      "flightdeck-zzzzzzzzzzzz.css",
      "flightdeck-6f7ad8f56f16.rb"
    ].each do |name|
      get "/flightdeck/assets/#{name}"
      assert_response :not_found, "expected #{name.inspect} to 404"
    end
  end

  test "the committed manifest matches the committed files" do
    manifest = JSON.parse(Flightdeck::Assets.root.join("manifest.json").read)

    assert_equal %w[flightdeck.css flightdeck.js].sort, manifest.keys.sort

    manifest.each do |logical, entry|
      path = Flightdeck::Assets.root.join(entry["file"])
      assert path.file?, "#{entry["file"]} for #{logical} is missing — run `rake assets:build`"

      contents = path.binread
      sha = Digest::SHA256.hexdigest(contents)

      assert_equal entry["sha256"], sha, "#{logical} contents do not match the manifest digest"
      assert_equal entry["digest"], sha[0, 12], "#{logical} digested filename is stale"
      assert_equal entry["size"], contents.bytesize
      assert_includes entry["file"], sha[0, 12]
    end
  end

  test "the bundle embeds the vendored fonts rather than fetching them" do
    css = Flightdeck::Assets.read(Flightdeck::Assets.digested_name("flightdeck.css"))

    assert_equal 5, css.scan("@font-face").size
    assert_includes css, "data:font/woff2;base64,"
    refute_includes css, "fonts.gstatic.com"
  end
end
