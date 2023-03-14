describe("OIDC auth plugin", function()
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
