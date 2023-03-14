local typedefs = require "kong.db.schema.typedefs"

return {
  name = "oidc",
  fields = {
    { claim_validators = {
      type = "array",
      required = false,
      elements = {
        type = "record",
        fields = {
          { claim = { type = "string", required = true }, },
          { matches = { type = "array", required = true, elements = { type = "string" } }, },
        },
      },
    }, },
  },
}
