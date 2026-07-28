# frozen_string_literal: true

require "test_helper"

class Flightdeck::AuthenticationTest < ActionDispatch::IntegrationTest
  test "unconfigured Flightdeck refuses to serve the dashboard" do
    get "/flightdeck"

    assert_response :unauthorized
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "FLIGHTDECK_USERNAME"
    assert_includes response.body, "base_controller_class"
    assert_includes response.body, "credentials:edit"
    assert_includes response.body, "skip_authentication"
  end

  test "skip_authentication serves the dashboard without credentials" do
    Flightdeck.config.skip_authentication = true

    get "/flightdeck"

    assert_response :success
    assert_includes response.body, "Flightdeck"
  end

  test "skip_authentication wins over configured HTTP Basic credentials" do
    with_env_basic_auth do
      Flightdeck.config.skip_authentication = true

      get "/flightdeck"

      assert_response :success
      assert_includes response.body, "Flightdeck"
    end
  end

  test "no credentials with HTTP Basic configured challenges the client" do
    with_env_basic_auth do
      get "/flightdeck"

      assert_response :unauthorized
      assert_match(/Basic realm="Flightdeck"/, response.headers["WWW-Authenticate"])
    end
  end

  test "correct credentials from the environment are accepted" do
    with_env_basic_auth do
      get "/flightdeck", headers: { "HTTP_AUTHORIZATION" => basic_auth_header("pilot", "correct-horse-battery") }

      assert_response :success
      assert_includes response.body, "Flightdeck"
    end
  end

  test "wrong password is rejected" do
    with_env_basic_auth do
      get "/flightdeck", headers: { "HTTP_AUTHORIZATION" => basic_auth_header("pilot", "wrong") }

      assert_response :unauthorized
    end
  end

  test "wrong username is rejected" do
    with_env_basic_auth do
      get "/flightdeck", headers: { "HTTP_AUTHORIZATION" => basic_auth_header("nobody", "correct-horse-battery") }

      assert_response :unauthorized
    end
  end

  test "explicitly configured credentials take precedence over the environment" do
    with_env_basic_auth(username: "env-user", password: "env-password") do
      Flightdeck.config.http_basic = { username: "explicit", password: "explicit-password" }

      get "/flightdeck", headers: { "HTTP_AUTHORIZATION" => basic_auth_header("env-user", "env-password") }
      assert_response :unauthorized

      get "/flightdeck", headers: { "HTTP_AUTHORIZATION" => basic_auth_header("explicit", "explicit-password") }
      assert_response :success
    end
  end

  test "credentials are re-read per request rather than memoized at boot" do
    get "/flightdeck"
    assert_response :unauthorized

    with_env_basic_auth do
      get "/flightdeck", headers: { "HTTP_AUTHORIZATION" => basic_auth_header("pilot", "correct-horse-battery") }
      assert_response :success
    end

    get "/flightdeck"
    assert_response :unauthorized
  end

  test "partially configured credentials do not authenticate" do
    ENV["FLIGHTDECK_USERNAME"] = "pilot"

    get "/flightdeck"
    assert_response :unauthorized
    assert_includes response.body, "FLIGHTDECK_PASSWORD"
  end

  test "assets are served without authentication" do
    get "/flightdeck/assets/#{Flightdeck::Assets.digested_name("flightdeck.css")}"

    assert_response :success
  end
end
