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

local type = type


ffi.cdef[[
typedef unsigned char xmlChar;
typedef int xmlElementType;
typedef struct _xmlDoc xmlDoc;
typedef xmlDoc *xmlDocPtr;
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

struct _xmlNs {
    xmlNsPtr next;
    xmlElementType type;
    const xmlChar *href;
    const xmlChar *prefix;
    void *_private;
    xmlDocPtr context;
};

struct _xmlAttr {
    void *_private;
    xmlElementType type;
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

struct _xmlNode {
    void *_private;
    xmlElementType type;
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

void xmlInitParser(void);
xmlDocPtr xmlReadMemory(const char *buffer, int size, const char *URL,
                        const char *encoding, int options);
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
xmlChar *xmlGetProp(const xmlNodePtr node, const xmlChar *name);
xmlChar *xmlNodeGetContent(const xmlNodePtr cur);

int xmlC14NDocDumpMemory(xmlDocPtr doc, xmlNodeSetPtr nodes,
                         int mode, xmlChar **inclusive_ns_prefixes,
                         int with_comments, xmlChar **doc_txt_ptr);
void xmlDocDumpMemoryEnc(xmlDocPtr out_doc, xmlChar **doc_txt_ptr,
                         int *doc_txt_len, const char *txt_encoding);
]]

local loaded, C = pcall(ffi.load, "xml2")
if not loaded then
    C = ffi.load("libxml2.so.2")
end
C.xmlInitParser()

local XML_ELEMENT_NODE = 1
local XML_DTD_NODE = 14
local XML_PARSE_NONET = 2048
local EXCLUSIVE_C14N = 1

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


function _M.parse(value)
    if type(value) ~= "string" or value == "" then
        return nil, "XML body is empty"
    end

    local doc = C.xmlReadMemory(value, #value, "document.xml", nil, XML_PARSE_NONET)
    if doc == nil then
        return nil, "failed to parse XML"
    end

    local child = ffi.cast("xmlNodePtr", doc).children
    while child ~= nil do
        if child.type == XML_DTD_NODE then
            C.xmlFreeDoc(doc)
            return nil, "DTD and entity declarations are not allowed"
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
        return by_href
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


function _M.content(node)
    return copy_and_free(C.xmlNodeGetContent(node))
end


local function canonicalize_document(doc)
    local output = ffi.new("xmlChar *[1]")
    local length = C.xmlC14NDocDumpMemory(doc, nil, EXCLUSIVE_C14N, nil, 0, output)
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


function _M.canonicalize_document(doc)
    return canonicalize_document(doc)
end


function _M.canonicalize(node)
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

    local result, err = canonicalize_document(doc)
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