local Util = require("autoinst.util")
local TS = vim.treesitter
local TSU = require 'nvim-treesitter.ts_utils'

local function get_squery(stext, query_string, root)
	local parser = TS.get_string_parser(stext, "verilog")
	local ok, query = pcall(TS.query.parse, parser:lang(), query_string)

	if not ok then
		print("Failed to parse query")
		print(query_string)
		return
	end

	local tree = parser:parse()[1]

	local nodes = {}
	if root == nil then
		root = tree:root()
	end
	for id, node, metadata in query:iter_captures(root, 0, 0, -1) do
		table.insert(nodes, node)
	end
	return nodes
end

local function get_query_nodes(stext, query_string, root)
	local parser
	if type(stext) == "string" then
		parser = TS.get_string_parser(stext, "verilog")
	elseif type(stext) == "number" then
		parser = TS.get_parser()
	else
		print("Invalid type for stext")
		vim.ui.input("Press enter to continue")
		return
	end
	local ok, query = pcall(TS.query.parse, parser:lang(), query_string)

	if not ok then
		print("Failed to parse query")
		print(query_string)
		return
	end

	local tree = parser:parse()[1]

	local nodes = {}
	if root == nil then
		root = tree:root()
	end
	for id, node, metadata in query:iter_captures(root, 0, 0, -1) do
		table.insert(nodes, node)
	end
	return nodes
end

local function get_query(stext, query_string, root)
	local parser
	if type(stext) == "string" then
		parser = TS.get_string_parser(stext, "verilog")
	else
		parser = TS.get_parser()
	end
	local ok, query = pcall(TS.query.parse, parser:lang(), query_string)

	if not ok then
		print("Failed to parse query")
		print(query_string)
		return
	end

	local tree = parser:parse()[1]

	local items = {}
	if root == nil then
		root = tree:root()
	end
	for id, node, metadata in query:iter_captures(root, 0, 0, -1) do
		local item = TS.get_node_text(node, stext, metadata[id])
		local sr,sc,er,ec = TS.get_node_range(node, stext) 
		table.insert(items, {text=item,start_row=sr,start_col=sc,end_row=er,end_col=ec})
	end
	return items
end

local function filter_children(node, filter)
	local result = {}
	if filter(node) then
		table.insert(result,node)
	else
		for child in node:iter_children() do
			local a = filter_children(child,filter)
			for _,v in ipairs(a) do
				table.insert(result,v)
			end
		end
	end
	return result
end

local function search_parents_for_type(node, type)
	--Searches the parents for a node of the given node type
	local cur_node = node
	while cur_node ~= nil do
		if cur_node:type() == type then
			return cur_node
		end
		cur_node = cur_node:parent()
	end
	return
end

local function search_children_for_type(node, type)
	--Searches all children for given type and returns the first node
	--that matches
	if node:type() == type then
		return node
	end
	for child in node:iter_children() do
		if child:type() == type then
			return child
		end
		local search_node = search_children_for_type(child,type)
		if search_node ~= nil then
			return search_node
		end
	end
	return
end

