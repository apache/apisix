std = "ngx_lua"
unused_args = false
redefined = false
max_line_length = 100

exclude_files = {
    "apisix/cli/ngx_tpl.lua",
}

files["apisix/patch.lua"] = {
    globals = {
        "math.randomseed",
    },
}
