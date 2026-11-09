--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local ffi = require("ffi")
local jit = require("jit")

local byte = string.byte
local find = string.find
local gmatch = string.gmatch
local sub = string.sub
local ipairs = ipairs
local pairs = pairs
local table_concat = table.concat
local table_sort = table.sort
local type = type


ffi.cdef[[
typedef unsigned char xmlChar;
typedef struct _xmlDoc xmlDoc;
typedef xmlDoc *xmlDocPtr;
typedef struct _xmlParserCtxt xmlParserCtxt;
typedef xmlParserCtxt *xmlParserCtxtPtr;
typedef struct _xmlError xmlError;
typedef xmlError *xmlErrorPtr;
typedef void (*xmlStructuredErrorFunc)(void *userData, xmlErrorPtr error);
typedef struct _xmlSAXHandler xmlSAXHandler;
typedef struct _xmlNode xmlNode;
typedef xmlNode *xmlNodePtr;
typedef struct _xmlNs xmlNs;
typedef xmlNs *xmlNsPtr;
typedef struct _xmlAttr xmlAttr;
typedef xmlAttr *xmlAttrPtr;
typedef struct _xmlNodeSet xmlNodeSet;
typedef xmlNodeSet *xmlNodeSetPtr;
typedef void (*xmlFreeFunc)(void *mem);
extern xmlFreeFunc xmlFree;
]]

-- FFI types are process-wide: struct bodies must only be declared once, or
-- reloading this module (for example on a plugin hot reload) fails with
-- "attempt to redefine".
if ffi.sizeof("struct _xmlSAXHandler") == nil then
    ffi.cdef[[
struct _xmlSAXHandler {
    void *internalSubset;
    void *isStandalone;
    void *hasInternalSubset;
    void *hasExternalSubset;
    void *resolveEntity;
    void *getEntity;
    void *entityDecl;
    void *notationDecl;
    void *attributeDecl;
    void *elementDecl;
    void *unparsedEntityDecl;
    void *setDocumentLocator;
    void *startDocument;
    void *endDocument;
    void *startElement;
    void *endElement;
    void *reference;
    void *characters;
    void *ignorableWhitespace;
    void *processingInstruction;
    void *comment;
    void *warning;
    void *error;
    void *fatalError;
    void *getParameterEntity;
    void *cdataBlock;
    void *externalSubset;
    unsigned int initialized;
    void *_private;
    void *startElementNs;
    void *endElementNs;
    xmlStructuredErrorFunc serror;
};
]]
end

if ffi.sizeof("struct _xmlParserCtxt") == nil then
    ffi.cdef[[
struct _xmlParserCtxt {
    xmlSAXHandler *sax;
};
]]
end

if ffi.sizeof("struct _xmlNs") == nil then
    ffi.cdef[[
struct _xmlNs {
    xmlNsPtr next;
    int type;
    const xmlChar *href;
    const xmlChar *prefix;
    void *_private;
    xmlDocPtr context;
};
]]
end

if ffi.sizeof("struct _xmlAttr") == nil then
    ffi.cdef[[
struct _xmlAttr {
    void *_private;
    int type;
    const xmlChar *name;
    xmlNodePtr children;
    xmlNodePtr last;
    xmlNodePtr parent;
    xmlAttrPtr next;
    xmlAttrPtr prev;
    xmlDocPtr doc;
    xmlNsPtr ns;
    int atype;
    void *psvi;
};
]]
end

if ffi.sizeof("struct _xmlNode") == nil then
    ffi.cdef[[
struct _xmlNode {
    void *_private;
    int type;
    const xmlChar *name;
    xmlNodePtr children;
    xmlNodePtr last;
    xmlNodePtr parent;
    xmlNodePtr next;
    xmlNodePtr prev;
    xmlDocPtr doc;
    xmlNsPtr ns;
    xmlChar *content;
    xmlAttrPtr properties;
    xmlNsPtr nsDef;
    void *psvi;
    unsigned short line;
    unsigned short extra;
};
]]
end

if ffi.sizeof("struct _xmlError") == nil then
    ffi.cdef[[
struct _xmlError {
    int domain;
    int code;
    char *message;
    int level;
};
]]
end

ffi.cdef[[
void xmlInitParser(void);
xmlParserCtxtPtr xmlNewParserCtxt(void);
xmlDocPtr xmlCtxtReadMemory(xmlParserCtxtPtr ctxt, const char *buffer, int size,
                            const char *URL, const char *encoding, int options);
void xmlFreeParserCtxt(xmlParserCtxtPtr ctxt);
void xmlFreeDoc(xmlDocPtr cur);
xmlNodePtr xmlDocGetRootElement(const xmlDoc *doc);
xmlDocPtr xmlNewDoc(const xmlChar *version);
xmlNodePtr xmlDocCopyNode(xmlNodePtr node, xmlDocPtr doc, int extended);
xmlNodePtr xmlDocSetRootElement(xmlDocPtr doc, xmlNodePtr root);

xmlNsPtr xmlNewNs(xmlNodePtr node, const xmlChar *href, const xmlChar *prefix);
xmlNsPtr xmlSearchNs(xmlDocPtr doc, xmlNodePtr node, const xmlChar *name_space);
xmlNsPtr xmlSearchNsByHref(xmlDocPtr doc, xmlNodePtr node, const xmlChar *href);
xmlNodePtr xmlNewNode(xmlNsPtr ns, const xmlChar *name);
xmlNodePtr xmlNewChild(xmlNodePtr parent, xmlNsPtr ns,
                       const xmlChar *name, const xmlChar *content);
xmlNodePtr xmlAddPrevSibling(xmlNodePtr cur, xmlNodePtr elem);
void xmlUnlinkNode(xmlNodePtr cur);
void xmlFreeNode(xmlNodePtr cur);

xmlAttrPtr xmlSetNsProp(xmlNodePtr node, xmlNsPtr ns,
                        const xmlChar *name, const xmlChar *value);
xmlAttrPtr xmlSetProp(xmlNodePtr node, const xmlChar *name,
                      const xmlChar *value);
xmlChar *xmlGetNsProp(const xmlNodePtr node, const xmlChar *name,
                      const xmlChar *name_space);
xmlChar *xmlGetNoNsProp(const xmlNodePtr node, const xmlChar *name);
xmlChar *xmlGetProp(const xmlNodePtr node, const xmlChar *name);
xmlChar *xmlNodeGetContent(const xmlNodePtr cur);
int xmlValidateNCName(const xmlChar *value, int space);

int xmlC14NDocDumpMemory(xmlDocPtr doc, xmlNodeSetPtr nodes,
                         int mode, xmlChar **inclusive_ns_prefixes,
                         int with_comments, xmlChar **doc_txt_ptr);
void xmlDocDumpMemoryEnc(xmlDocPtr out_doc, xmlChar **doc_txt_ptr,
                         int *doc_txt_len, const char *txt_encoding);
]]

local loaded, C = pcall(ffi.load, "xml2")
if not loaded then
    local lib
    loaded, lib = pcall(ffi.load, "libxml2.so.2")
    if not loaded then
        error("libxml2 is not available, install the libxml2 package "
              .. "(for example `apt-get install -y libxml2`): " .. tostring(lib), 0)
    end
    C = lib
end
C.xmlInitParser()

local XML_ELEMENT_NODE = 1
local XML_TEXT_NODE = 3
local XML_CDATA_SECTION_NODE = 4
local XML_DTD_NODE = 14
local XML_ERR_ERROR = 2
local XML_PARSE_NONET = 2048
local XML_PARSE_NOERROR = 32
local XML_PARSE_NOWARNING = 64
local EXCLUSIVE_C14N = 1
local XML_ID_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
local WSU_ID_NAMESPACE = "http://docs.oasis-open.org/wss/2004/01/"
                          .. "oasis-200401-wss-wssecurity-utility-1.0.xsd"

local DTD_ERROR = "DTD and entity declarations are not allowed"

-- libxml2 2.9 (the version in Debian bookworm based APISIX images) compares
-- every attribute of an element with the ones before it and resolves every
-- element and attribute name against all namespace declarations in scope.
-- Many attributes on one element, or many namespace declarations in scope,
-- therefore cost super-linear CPU time while the NGINX worker is blocked.
-- Reject such documents before they reach the parser; real documents stay
-- far below these limits.
local MAX_ATTRIBUTES_PER_ELEMENT = 256
local MAX_NAMESPACES_IN_SCOPE = 128
-- The shortest possible attribute is 5 bytes (` a=""`), so only a markup
-- segment longer than this can hold too many attributes.
local MIN_SUSPICIOUS_SEGMENT = MAX_ATTRIBUTES_PER_ELEMENT * 5
local ATTRIBUTE_PATTERN = "%s[^%s=<>\"']+%s*=%s*[\"']"
local NAMESPACE_DECLARATION_PATTERN = "%sxmlns[%s:=]"
-- Prefixes of QName-like content such as `xsi:type="ns:Type"` (ASCII or UTF-8
-- NCName characters before a colon that is followed by a name start).
local CONTENT_PREFIX_PATTERN = "([%a_\128-\255][%w_%.%-\128-\255]*):[%a_\128-\255]"
-- libxml2 looks up every PrefixList entry for every canonicalized element, so
-- the list must stay short: 8 entries cost at most about 0.8 s for 5 MB.
local MAX_CONTENT_PREFIXES = 8
-- Ignore the encoding declaration, so that the parser reads exactly the bytes
-- the limit checks above scanned. An explicit "UTF-8" encoding argument is not
-- used: it routes input through a conversion buffer limited to about 10 MB.
local XML_PARSE_IGNORE_ENC = 2097152
local UTF8_BOM = "\239\187\191"

local _M = {}


local function xml_char(value)
    if value == nil then
        return nil
    end
    return ffi.cast("const xmlChar *", value)
end


local function copy_and_free(value)
    if value == nil then
        return nil
    end
    local result = ffi.string(value)
    C.xmlFree(value)
    return result
end


-- Count occurrences of `needle` in value[first..last], stopping after
-- `limit`. The search runs on the segment only: searching `value` from
-- `first` would scan to the end of the document whenever the segment has no
-- match, which makes the caller quadratic.
local function count_plain(value, needle, first, last, limit)
    local count = 0
    local segment = sub(value, first, last)
    local position = 1
    while count <= limit do
        local found = find(segment, needle, position, true)
        if not found then
            break
        end
        count = count + 1
        position = found + 1
    end
    return count
end


-- Attribute values cannot contain "<", so every attribute of an element is
-- inside the segment between its "<" and the next "<". Counting may include
-- text that looks like attributes, which only makes the check stricter.
local function has_too_many_attributes(value)
    local start = find(value, "<", 1, true)
    while start do
        local next_start = find(value, "<", start + 1, true)
        local stop = (next_start or #value + 1) - 1
        if stop - start >= MIN_SUSPICIOUS_SEGMENT
           and count_plain(value, "=", start, stop, MAX_ATTRIBUTES_PER_ELEMENT)
               > MAX_ATTRIBUTES_PER_ELEMENT then
            local count = 0
            for _ in gmatch(sub(value, start, stop), ATTRIBUTE_PATTERN) do
                count = count + 1
                if count > MAX_ATTRIBUTES_PER_ELEMENT then
                    return true
                end
            end
        end
        start = next_start
    end
    return false
end


local function count_namespace_declarations(chunk)
    if not find(chunk, "xmlns", 1, true) then
        return 0
    end
    local count = 0
    for _ in gmatch(chunk, NAMESPACE_DECLARATION_PATTERN) do
        count = count + 1
    end
    return count
end


-- Track the namespace declarations in scope while walking the markup.
-- Quoted attribute values, comments, CDATA sections and processing
-- instructions are skipped, so only real declarations are counted; markup
-- that cannot be scanned is left to libxml2, which rejects it.
local function has_too_many_namespaces_in_scope(value)
    local declared = {}
    local depth = 0
    local in_scope = 0
    local position = 1
    while true do
        local start = find(value, "<", position, true)
        if not start then
            return false
        end
        local next_char = byte(value, start + 1)
        if next_char == 33 then                                    -- "<!"
            if sub(value, start, start + 3) == "<!--" then
                local close = find(value, "-->", start + 4, true)
                if not close then
                    return false
                end
                position = close + 3
            elseif sub(value, start, start + 8) == "<![CDATA[" then
                local close = find(value, "]]>", start + 9, true)
                if not close then
                    return false
                end
                position = close + 3
            else
                return false, DTD_ERROR
            end
        elseif next_char == 63 then                                -- "<?"
            local close = find(value, "?>", start + 2, true)
            if not close then
                return false
            end
            position = close + 2
        elseif next_char == 47 then                                -- "</"
            local close = find(value, ">", start + 2, true)
            if not close then
                return false
            end
            if depth > 0 then
                in_scope = in_scope - declared[depth]
                declared[depth] = nil
                depth = depth - 1
            end
            position = close + 1
        else                                                       -- start tag
            local declarations = 0
            local cursor = start + 1
            local tag_end
            while true do
                local stop = find(value, "[\"'>]", cursor)
                if not stop then
                    return false
                end
                declarations = declarations + count_namespace_declarations(
                    sub(value, cursor - 1, stop - 1))
                local stop_char = byte(value, stop)
                if stop_char == 62 then                            -- ">"
                    tag_end = stop
                    break
                end
                local close_quote = find(value, stop_char == 34 and '"' or "'",
                                         stop + 1, true)
                if not close_quote then
                    return false
                end
                cursor = close_quote + 1
            end
            if in_scope + declarations > MAX_NAMESPACES_IN_SCOPE then
                return true
            end
            if byte(value, tag_end - 1) ~= 47 then                -- not "/>"
                depth = depth + 1
                declared[depth] = declarations
                in_scope = in_scope + declarations
            end
            position = tag_end + 1
        end
    end
end


-- Returns an error message if the document exceeds the parser limits.
local function check_parser_limits(value)
    if has_too_many_attributes(value) then
        return "an element has more than " .. MAX_ATTRIBUTES_PER_ELEMENT
               .. " attributes"
    end
    -- Without enough declarations in the whole document, none can be
    -- exceeded in scope; this keeps the common case cheap.
    if count_plain(value, "xmlns", 1, #value, MAX_NAMESPACES_IN_SCOPE)
       > MAX_NAMESPACES_IN_SCOPE then
        local exceeded, err = has_too_many_namespaces_in_scope(value)
        if err then
            return err
        end
        if exceeded then
            return "more than " .. MAX_NAMESPACES_IN_SCOPE
                   .. " namespace declarations are in scope"
        end
    end
end


-- libxml2 reports recoverable errors, such as undeclared namespace prefixes,
-- through the structured error handler while still returning a document.
-- LuaJIT has a fixed number of FFI callback slots, so the handler is created
-- once per module load instead of once per request. Parsing is synchronous,
-- so a module-level flag is safe within a worker.
local parse_failed = false
local structured_error = ffi.cast("xmlStructuredErrorFunc", function(_, error)
    if error ~= nil and error.level >= XML_ERR_ERROR then
        parse_failed = true
    end
end)


local function read_memory(ctxt, value)
    parse_failed = false
    ctxt.sax.serror = structured_error
    local doc = C.xmlCtxtReadMemory(
        ctxt, value, #value, "document.xml", nil,
        XML_PARSE_NONET + XML_PARSE_NOERROR + XML_PARSE_NOWARNING + XML_PARSE_IGNORE_ENC)
    return doc, parse_failed
end
-- A C function that calls back into Lua must not be called from a
-- JIT-compiled trace, otherwise LuaJIT raises "bad callback".
jit.off(read_memory)


-- Only UTF-8 is accepted; the encoding declaration is ignored.
function _M.parse(value)
    if type(value) ~= "string" or value == "" then
        return nil, "XML body is empty"
    end
    -- libxml2 detects UTF-16, UTF-32 and EBCDIC from the first bytes, which
    -- would hide markup from the byte-based limit checks. UTF-16 and UTF-32
    -- markup contains NUL bytes, which XML never allows, and a UTF-8 document
    -- starts with "<" after an optional byte order mark and whitespace.
    local first = sub(value, 1, 3) == UTF8_BOM and 4 or 1
    if find(value, "\0", 1, true) or not find(value, "^%s*<", first) then
        return nil, "only UTF-8 encoded XML is supported"
    end
    local limit_err = check_parser_limits(value)
    if limit_err then
        return nil, limit_err
    end

    local ctxt = C.xmlNewParserCtxt()
    if ctxt == nil then
        return nil, "failed to create XML parser context"
    end

    local doc, has_error = read_memory(ctxt, value)
    C.xmlFreeParserCtxt(ctxt)
    if doc == nil or has_error then
        if doc ~= nil then
            C.xmlFreeDoc(doc)
        end
        return nil, "failed to parse XML"
    end

    local child = ffi.cast("xmlNodePtr", doc).children
    while child ~= nil do
        if child.type == XML_DTD_NODE then
            C.xmlFreeDoc(doc)
            return nil, DTD_ERROR
        end
        child = child.next
    end

    ffi.gc(doc, C.xmlFreeDoc)
    return doc
end


function _M.free_document(doc)
    if doc ~= nil then
        ffi.gc(doc, nil)
        C.xmlFreeDoc(doc)
    end
end


function _M.root(doc)
    return C.xmlDocGetRootElement(doc)
end


function _M.name(node)
    if node == nil or node.name == nil then
        return nil
    end
    return ffi.string(node.name)
end


function _M.namespace_uri(node)
    if node == nil or node.ns == nil or node.ns.href == nil then
        return ""
    end
    return ffi.string(node.ns.href)
end


function _M.each_child(parent)
    local current = parent ~= nil and parent.children or nil
    return function()
        while current ~= nil do
            local node = current
            current = current.next
            if node.type == XML_ELEMENT_NODE then
                return node
            end
        end
    end
end


-- Whether `node` has child elements or non-whitespace text. Comments and
-- processing instructions do not count.
function _M.has_content(node)
    local child = node.children
    while child ~= nil do
        if child.type == XML_ELEMENT_NODE then
            return true
        end
        if (child.type == XML_TEXT_NODE or child.type == XML_CDATA_SECTION_NODE)
           and child.content ~= nil
           and ffi.string(child.content):find("%S") then
            return true
        end
        child = child.next
    end
    return false
end


function _M.walk(root, visit)
    visit(root)
    for child in _M.each_child(root) do
        _M.walk(child, visit)
    end
end


function _M.find_child(parent, namespace_uri, local_name)
    for child in _M.each_child(parent) do
        if _M.name(child) == local_name and _M.namespace_uri(child) == namespace_uri then
            return child
        end
    end
end


function _M.find_all(root, namespace_uri, local_name)
    local result = {}
    _M.walk(root, function(node)
        if _M.name(node) == local_name and _M.namespace_uri(node) == namespace_uri then
            result[#result + 1] = node
        end
    end)
    return result
end


function _M.ensure_namespace(doc, node, prefix, href)
    local by_href = C.xmlSearchNsByHref(doc, node, xml_char(href))
    if by_href ~= nil and by_href.prefix ~= nil then
        local existing = C.xmlSearchNs(doc, node, by_href.prefix)
        if existing ~= nil and existing.href ~= nil
           and ffi.string(existing.href) == href then
            return existing
        end
    end

    local suffix = 0
    while true do
        local candidate = suffix == 0 and prefix or prefix .. suffix
        local existing = C.xmlSearchNs(doc, node, xml_char(candidate))
        if existing == nil then
            return C.xmlNewNs(node, xml_char(href), xml_char(candidate))
        end
        if existing.href ~= nil and ffi.string(existing.href) == href then
            return existing
        end
        suffix = suffix + 1
    end
end


local function prefix_token(ns)
    if ns.prefix == nil then
        return "#default"
    end
    return ffi.string(ns.prefix)
end


-- Exclusive canonicalization only renders the namespace declarations that
-- element and attribute names use. A prefix that content refers to, such as
-- `ns` in `xsi:type="ns:Type"`, would otherwise not be protected: its
-- declaration can be changed, or a new one inserted on an intermediate
-- element, without changing the digest. Returns, sorted, the declared
-- prefixes that text or attribute values inside `node` refer to, for the
-- InclusiveNamespaces PrefixList, or nil and an error when there are more
-- than MAX_CONTENT_PREFIXES of them.
function _M.content_namespace_prefixes(node)
    local declared = {}
    local referenced = {}

    local function declare(ns)
        while ns ~= nil do
            if ns.prefix ~= nil and ns.href ~= nil and ns.href[0] ~= 0 then
                declared[ffi.string(ns.prefix)] = true
            end
            ns = ns.next
        end
    end

    local function scan(child)
        while child ~= nil do
            if (child.type == XML_TEXT_NODE or child.type == XML_CDATA_SECTION_NODE)
               and child.content ~= nil then
                local text = ffi.string(child.content)
                if find(text, ":", 1, true) then
                    for prefix in gmatch(text, CONTENT_PREFIX_PATTERN) do
                        referenced[prefix] = true
                    end
                end
            end
            child = child.next
        end
    end

    local ancestor = node.parent
    while ancestor ~= nil and ancestor.type == XML_ELEMENT_NODE do
        declare(ancestor.nsDef)
        ancestor = ancestor.parent
    end
    _M.walk(node, function(element)
        declare(element.nsDef)
        scan(element.children)
        local attribute = element.properties
        while attribute ~= nil do
            scan(attribute.children)
            attribute = attribute.next
        end
    end)

    local prefixes = {}
    for prefix in pairs(referenced) do
        if declared[prefix] and prefix ~= "xml" and prefix ~= "xmlns" then
            prefixes[#prefixes + 1] = prefix
        end
    end
    if #prefixes > MAX_CONTENT_PREFIXES then
        return nil, "more than " .. MAX_CONTENT_PREFIXES
                    .. " namespace prefixes are referenced in content"
    end
    table_sort(prefixes)
    return prefixes
end


function _M.prefix_list(prefixes)
    return table_concat(prefixes, " ")
end


function _M.new_child(parent, namespace, local_name, content)
    return C.xmlNewChild(parent, namespace, xml_char(local_name), xml_char(content))
end


function _M.new_node(namespace, local_name)
    return C.xmlNewNode(namespace, xml_char(local_name))
end


function _M.add_before(existing, child)
    return C.xmlAddPrevSibling(existing, child)
end


function _M.remove(node)
    C.xmlUnlinkNode(node)
    C.xmlFreeNode(node)
end


function _M.set_namespaced_property(node, namespace, name, value)
    return C.xmlSetNsProp(node, namespace, xml_char(name), xml_char(value))
end


function _M.set_property(node, name, value)
    return C.xmlSetProp(node, xml_char(name), xml_char(value))
end


function _M.get_namespaced_property(node, namespace_uri, name)
    return copy_and_free(C.xmlGetNsProp(node, xml_char(name), xml_char(namespace_uri)))
end


function _M.get_property(node, name)
    return copy_and_free(C.xmlGetProp(node, xml_char(name)))
end


function _M.id_values(node)
    local values = {}
    local attribute = node.properties
    while attribute ~= nil do
        local name = ffi.string(attribute.name)
        local namespace_uri
        if attribute.ns ~= nil and attribute.ns.href ~= nil then
            namespace_uri = ffi.string(attribute.ns.href)
        end

        if (name == "Id" and (namespace_uri == nil
                              or namespace_uri == WSU_ID_NAMESPACE))
           or (name == "id" and namespace_uri == XML_ID_NAMESPACE) then
            local value
            if namespace_uri then
                value = copy_and_free(C.xmlGetNsProp(
                    node, xml_char(name), xml_char(namespace_uri)))
            else
                value = copy_and_free(C.xmlGetNoNsProp(node, xml_char(name)))
            end
            if value then
                values[#values + 1] = value
            end
        end
        attribute = attribute.next
    end
    return values
end


function _M.valid_id(value)
    return C.xmlValidateNCName(xml_char(value), 0) == 0
end


function _M.content(node)
    return copy_and_free(C.xmlNodeGetContent(node))
end


-- `prefixes` is the InclusiveNamespaces PrefixList as a Lua array, or nil.
local function canonicalize_document(doc, prefixes)
    local inclusive
    if prefixes and #prefixes > 0 then
        -- the Lua strings in `prefixes` stay referenced until the call returns
        inclusive = ffi.new("xmlChar *[?]", #prefixes + 1)
        for i, prefix in ipairs(prefixes) do
            inclusive[i - 1] = ffi.cast("xmlChar *", prefix)
        end
    end
    local output = ffi.new("xmlChar *[1]")
    local length = C.xmlC14NDocDumpMemory(doc, nil, EXCLUSIVE_C14N, inclusive, 0, output)
    if length < 0 or output[0] == nil then
        if output[0] ~= nil then
            C.xmlFree(output[0])
        end
        return nil, "canonicalization failed"
    end

    local result = ffi.string(output[0], length)
    C.xmlFree(output[0])
    return result
end


function _M.canonicalize_document(doc, prefixes)
    return canonicalize_document(doc, prefixes)
end


-- Canonicalize `node` as an apex element. The copy only carries the
-- namespace declarations that names inside it use, so declarations named in
-- `prefixes` that are in scope at `node` are added to the copy's root.
function _M.canonicalize(node, prefixes)
    local doc = C.xmlNewDoc(xml_char("1.0"))
    if doc == nil then
        return nil, "failed to create canonicalization document"
    end

    local copy = C.xmlDocCopyNode(node, doc, 1)
    if copy == nil then
        C.xmlFreeDoc(doc)
        return nil, "failed to copy canonicalization node"
    end
    C.xmlDocSetRootElement(doc, copy)

    for _, token in ipairs(prefixes or {}) do
        local prefix = token ~= "#default" and token or nil
        local declared = false
        local ns = copy.nsDef
        while ns ~= nil do
            if prefix_token(ns) == token then
                declared = true
                break
            end
            ns = ns.next
        end
        if not declared then
            local in_scope = C.xmlSearchNs(node.doc, node, xml_char(prefix))
            if in_scope ~= nil and in_scope.href ~= nil then
                C.xmlNewNs(copy, in_scope.href, xml_char(prefix))
            end
        end
    end

    local result, err = canonicalize_document(doc, prefixes)
    C.xmlFreeDoc(doc)
    return result, err
end


function _M.serialize(doc)
    local output = ffi.new("xmlChar *[1]")
    local length = ffi.new("int[1]")
    C.xmlDocDumpMemoryEnc(doc, output, length, "UTF-8")
    if output[0] == nil then
        return nil, "XML serialization failed"
    end

    local result = ffi.string(output[0], length[0])
    C.xmlFree(output[0])
    return result
end


return _M
