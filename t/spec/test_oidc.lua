local helpers = require("spec.helpers")
local cjson = require("cjson")

describe("OIDC auth plugin", function()
  local proxy_client

  setup(function()
    helpers.run_migrations()

    -- Start Apisix and configure it to use Kong OIDC auth plugin
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-oidc-auth",
      hosts = { "test.com" },
      upstream_url = "http://httpbin.org",
      plugins = {
        ["oidc-auth"] = {
          scopes = { "openid" },
          client_id = "client_id",
          client_secret = "client_secret",
          discovery = "https://accounts.google.com/.well-known/openid-configuration",
          redirect_uri_path = "/callback",
          logout_path = "/logout",
          redirect_after_logout_uri = "http://localhost:8080"
        }
      }
    })

    assert(helpers.start_kong {
      plugins = "oidc-auth",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      lua_ssl_trusted_certificate = "./spec/fixtures/kong_spec.crt",
      admin_listen = "127.0.0.1:8001",
      proxy_listen = "127.0.0.1:8000",
      stream_listen = "127.0.0.1:9000"
    })

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong(nil, true)
  end)

  it("should allow access when claim_validators is missing or empty", function()
    local response = assert(proxy_client:send {
      method = "GET",
      path = "/get",
      headers = {
        ["Authorization"] = "Bearer " .. good_token
      }
    })

    assert.response(response).has.status(200)
  end)

  it("should allow access when the custom claim matches an allowed value", function()
    local response = assert(proxy_client:send {
      method = "GET",
      path = "/get",
      headers = {
        ["Authorization"] = "Bearer " .. good_token_with_allowed_claim
      }
    })

    assert.response(response).has.status(200)
  end)

  it("should deny access when the custom claim does not match any allowed value", function()
    local response = assert(proxy_client:send {
      method = "GET",
      path = "/get",
      headers = {
        ["Authorization"] = "Bearer " .. good_token_with_disallowed_claim
      }
    })

    assert.response(response).has.status(401)
  end)
end)

