local Util = require("autoinst.util")
local TS = vim.treesitter
local TSU = require 'nvim-treesitter.ts_utils'
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local entry_display = require "telescope.pickers.entry_display"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"

local autoinst = {}
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

function get_header_items(file_path)
	local stext = io.open(file_path):read("*a")
	local module_name = get_query(stext, "((module_keyword) (simple_identifier) @module_name)")
	local name = {
		module_name = module_name[1],
		instance_name = {text="",start_row=0,start_col=0,end_row=0,end_col=0},
	}
	local params = {
		idents = get_query(
			stext,
			"(parameter_declaration (list_of_param_assignments (param_assignment (simple_identifier) @param_name )))"
		),
		values = get_query(
			stext,
			"(parameter_declaration (list_of_param_assignments (param_assignment (constant_param_expression) @param_value)))"
		),
	}

	local ports = {
		idents = get_query(stext, "[(ansi_port_declaration (simple_identifier) @ansi_name) (port (simple_identifier) @nonansi_name)]"),
		values = get_query(stext, "[(ansi_port_declaration (simple_identifier) @ansi_name) (port (simple_identifier) @nonansi_name)]"),
		types = get_query(stext, "(port_declaration . (_) @PortType)"),
	}
	if #ports.types == 0 then
		ports.types = get_query(stext,"(net_port_header (port_direction) @direction)")
	else
		for i=1,#ports.types do
			if string.sub(ports.types[i].text,1,1) == "i" then
				ports.types[i].text = string.sub(ports.types[i].text,1,5)
			else
				ports.types[i].text = string.sub(ports.types[i].text,1,6)
			end
		end
	end

	return {
		name = name,
		params = params,
		ports = ports,
	}
end

function get_instantiation_items(stext)

	local module_name = get_query(stext, "(module_instantiation instance_type: (simple_identifier) @module_name)")
	local instance_name = get_query(stext, "(name_of_instance instance_name: (simple_identifier) @module_name)")
	local name = {
		module_name = module_name[1],
		instance_name = instance_name[1],
	}
	local params = {
		idents = get_query(stext, "(named_parameter_assignment (simple_identifier) @parameter_name)"),
		values = get_query(stext, "((param_expression) @parameter_values)"),
	}
	local full_port = get_query(stext, "((named_port_connection) @port)")
	local ports = {
		idents = get_query(stext, "(named_port_connection port_name : (simple_identifier) @port)"),
		values = get_query(stext, "(named_port_connection connection : (expression) @port)"),
	}
	for i,port in ipairs(full_port) do
		if port.end_col == ports.idents[i].end_col+2 then
			table.insert(ports.values,i,{text="",start_col=port.end_col-1,end_col=port.end_col-1,start_row=port.start_row,end_row=port.end_row})
		end
	end

	return {
		name = name,
		params = params,
		ports = ports,
	}
end

local function gen_inst(items)
	local fmt_ptn = ".%s(%s)"
	local inst_code = {}
	local inst_line = ""
	if #items.params.idents > 0 then
		table.insert(inst_code, items.name.module_name.text .. " #(")
		for i, ident in ipairs(items.params.idents) do
			local parameter_value = items.params.values[i].text
			if i == #items.params.idents then
				inst_line = string.format(fmt_ptn, ident.text, parameter_value)
			else
				inst_line = string.format(fmt_ptn .. ",", ident.text, parameter_value)
			end
			table.insert(inst_code, inst_line)
		end
		table.insert(inst_code, string.format(") %s(", items.name.instance_name.text))
	else
		inst_line = string.format("%s %s(", items.name.module_name.text, items.name.instance_name.text)
		table.insert(inst_code, inst_line)
	end

	for i, port in ipairs(items.ports.idents) do
		local port_connection = items.ports.values[i].text
		if i == #items.ports.idents then
			inst_line = string.format(fmt_ptn, port.text, port_connection)
		else
			inst_line = string.format(fmt_ptn .. ",", port.text, port_connection)
		end
		table.insert(inst_code, inst_line)
	end
	table.insert(inst_code, ");")

	return inst_code
end

local function get_instantiation_at_location(r, c)
	local filetype = vim.api.nvim_buf_get_option(0, "ft")
	local lang = require("nvim-treesitter.parsers").ft_to_lang(filetype)
	local module_types = "(module_instantiation instance_type: (simple_identifier) @modules)"
	local modules = "((module_instantiation) @modules)"
	local plist_query = vim.treesitter.query.parse(lang, modules)
	local type_query = vim.treesitter.query.parse(lang, module_types)
	local tree = vim.treesitter.get_parser():parse()[1]
	local type = "";
	local current_instantiation = "";
	local ci_sr = 0
	local ci_er = 0
	for id, node, metadata in plist_query:iter_captures(tree:root(), 0) do
		-- Print the node name and source text.
		local sr, sc, er, ec = vim.treesitter.get_node_range(node, vim.api.nvim_get_current_buf())
		if sr <= r and er >= r then
			current_instantiation = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf(), metadata[id])
			ci_sr = sr
			ci_er = er
			for id2, node2, metadata2 in type_query:iter_captures(tree:root(), 0) do
				local tsr, tsc, ter, tec = vim.treesitter.get_node_range(node2, vim.api.nvim_get_current_buf())
				if tsr >= sr and tsr < er then
					type = vim.treesitter.get_node_text(node2, vim.api.nvim_get_current_buf(), metadata[id2])
					return {
						starting_row = sr,
						ending_row = er,
						type = type,
						text = current_instantiation
					}
				end
			end
		end
	end
	vim.print("Error: could not find module instantiation at cursor")
	return {}
end

local function inst_with_path(path)
	local full_path = ""
	if Util.is_not_root_pattern(path) then
		full_path = path
	else
		local root = Util.get_root()
		full_path = root .. "/" .. path
	end

	local items = get_header_items(full_path)
	if items == nil then
		return
	end
	local inst_code = gen_inst(items)
	vim.api.nvim_put(inst_code, "l", false, true)
end

local function inst_with_telescope()
	Util.telescope(inst_with_path)
end

local function auto_instantiation(args)
	if args == "" then
		inst_with_telescope()
	else
		inst_with_path(args)
	end
end

local function update_instantiation()
	-- Get current cursor location
	local r,c = unpack(vim.api.nvim_win_get_cursor(0))
	-- Get the module being instantiated at the cursor location
	local module_instantiation = get_instantiation_at_location(r,c)
	-- Search for a (system)verilog file with the same name as the module type
	local file_path = Util.file_search(module_instantiation.type)
	-- Get the module items (parameters and ports) from the module declaration
	local module_items = get_header_items(file_path)
	-- Get the module items in the instance
	local instantiated_items = get_instantiation_items(module_instantiation.text)
	-- If a port/param exists in the current instantiation then take its assignment from that
	-- otherwise use the default assignment
	module_items.name.instance_name.text = instantiated_items.name.instance_name.text
	for i, parameter in ipairs(module_items.params.idents) do
		for j, inst_param in ipairs(instantiated_items.params.idents) do
			if inst_param.text == parameter.text then
				module_items.params.values[i].text = instantiated_items.params.values[j].text
				break
			end
		end
	end
	for i, port in ipairs(module_items.ports.idents) do
		for j, inst_port in ipairs(instantiated_items.ports.idents) do
			if inst_port.text == port.text then
				local value = ""
				if instantiated_items.ports.values[j] ~= nil then
					value = instantiated_items.ports.values[j].text
				end
				module_items.ports.values[i].text = value
				-- vim.print(inst_port.text .. " | " .. port.text .. " | " .. value)
				break
			end
		end
	end
	-- vim.print(instantiated_items)
	-- Convert the items into an instantiation and replace the current one with the new one
	local inst_code = gen_inst(module_items)
	vim.print(inst_code)
	vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(),module_instantiation.starting_row,module_instantiation.ending_row+1,true,inst_code)
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

local function filter(t, filt)
	local result = {}
	for _,elem in ipairs(t) do
		if filt(elem) then
			table.insert(result,elem)
		end
	end
	return result
end

local function get_shared_parents(n1,n2)
	local n1p = {}
	local ids = {}
	parent = n1:parent()
	while parent ~= nil do
		table.insert(n1p, parent)
		table.insert(ids, parent:id())
		parent = parent:parent()
	end
	local shared = {}
	parent = n2:parent()
	while parent ~= nil do
		local id = parent:id()
		for idx,n1_id in ipairs(ids) do
			if n1_id == id then
				table.insert(shared, parent)
				break
			end
		end
		parent = parent:parent()
	end
	return shared
end
 
local function replace_port(node, connection)
	name = TS.get_node_text(node:named_child(0),0)
	line = "." .. name .. "(" .. connection .. ")"
	local sr,sc,er,ec = TS.get_node_range(node, 0) 
	vim.api.nvim_buf_set_text(0, sr, sc, er, ec, {line})
end

local function connect_ports()
	--Get the port that the cursor is on
	local cursor_port = TSU.get_node_at_cursor(0)
	cursor_port = search_parents_for_type(cursor_port, 'named_port_connection') 
	local cursor_module = search_parents_for_type(cursor_port, 'module_instantiation')
	-- Create list of all ports that this could be connected to
	-- Going to start with just all ports instantiated in current module
	-- then can filter based on direction and widths later
	local instances = get_query_nodes(0, "((module_instantiation) @modules)")
	local port_table = {}
	for i, instance in ipairs(instances) do
		local instance_name = TS.get_node_text(search_children_for_type(instance,'name_of_instance'),0)
		local instance_type = TS.get_node_text(instance:named_child(0),0)
		local list_of_ports = search_children_for_type(instance, 'list_of_port_connections')
		for port in list_of_ports:iter_children() do
			if port:type() == 'named_port_connection' then
				local port_name = TS.get_node_text(port:named_child(0),0)
				local port_value
				if port:named_child_count() >= 2 then
					port_value = TS.get_node_text(port:named_child(1),0)
				end
				table.insert(port_table,{
					module_name=instance_type,
					instance_name = instance_name,
					port_name = TS.get_node_text(port:named_child(0),0),
					port_value = port_value,
					port = port,
				})
				-- vim.print(TS.get_node_text(port,0))
			end
		end
	end


	local function inst_connections(selection)
		local selected_port = selection.value.port
		-- Now I need to check that at most one port is already connected to a net
		-- If no ports are connected then I need to:

		-- 	Get the type from the module declaration
		-- 	Instantiate the type in the current module 
		-- vim.print(imod_items.name.instance_name)
		local selection_connected = selection.value.port_value ~= nil
		local cursor_connected = cursor_port:named_child_count() >= 2
		local net = ""
		if selection_connected and cursor_connected then
			vim.print("Both ports are already connected to a net")
			return
		elseif selection_connected then
			net = selection.value.port_value
			replace_port(cursor_port,net)
		elseif cursor_connected then
			net = TS.get_node_text(cursor_port:named_child(1),0)
			replace_port(selected_port,net)
		else
			local default_net_name = TS.get_node_text(cursor_port:named_child(0),0)
			net = vim.fn.input("Net Name: ", default_net_name, "file")
			replace_port(selected_port,net)
			replace_port(cursor_port,net)
			local file_path = Util.file_search(TS.get_node_text(cursor_module:named_child(0),0))
			local stext = io.open(file_path):read("*a")
			local port_declarations = get_squery(stext,"([(ansi_port_declaration) (port_declaration)] @port_list)")
			-- Get the module items (parameters and ports) from the module declaration
			local search_name = TS.get_node_text(cursor_port:named_child(0),0)
			local declaration = ''
			local pd
			local ud
			local net_type = 'wire'
			for _,port in ipairs(port_declarations) do
				if port:type() == 'ansi_port_declaration' then
					local name = TS.get_node_text(port:named_child(1),stext)
					if(name == search_name) then
						pd = filter_children(port,function(val)
							return val:type() == 'packed_dimension' 
						end)
						ud = filter_children(port,function(val) return val:type() == 'unpacked_dimension' end)
						local vector_type = search_children_for_type(port,'integer_vector_type')
						local net_port = search_children_for_type(port, 'net_port_header')
						local use_wire = (vector_type ~= nil) or (net_port ~= nil)
						if use_wire == false then
							local nt_node = search_children_for_type(port, 'data_type')
							net_type = TS.get_node_text(nt_node:child(0),stext)
						end
						break
					end

				elseif port:type() == 'port_declaration' then
					local port_names = filter_children(port, function(val)
						return (val:type() == 'list_of_variable_port_identifiers' or val:type() == 'list_of_variable_identifiers')
					end)
					-- local port_names = search_children_for_type(port, 'list_of_variable_port_identifiers')
					for id in port_names[1]:iter_children() do
						if TS.get_node_text(id,stext) == search_name then
							pd = filter_children(port,function(val)
								return val:type() == 'packed_dimension' 
							end)
							ud = {}
							local next_node = id:next_sibling()
							while next_node ~= nil and next_node:type() == "unpacked_dimension" do
								table.insert(ud,next_node)
								next_node = next_node:next_sibling()
							end
							local vector_type = search_children_for_type(port,'integer_vector_type')
							local net_port = search_children_for_type(port, 'net_port_type')
							local use_wire = (vector_type ~= nil) or (net_port ~= nil)
							if use_wire == false then
								local nt_node = search_children_for_type(port, 'data_type')
								net_type = TS.get_node_text(nt_node:child(0),stext)
							end
							break
						end
					end
				end
			end
			declaration = net_type .. ' '
			for _,d in ipairs(pd) do
				declaration = declaration .. TS.get_node_text(d,stext)
			end
			declaration = declaration .. ' ' .. net
			for _,d in ipairs(ud) do
				declaration = declaration .. TS.get_node_text(d,stext)
			end
			declaration = declaration .. ';'
			--TODO: Find where to place the net declaration
			local selected_module = search_parents_for_type(selected_port, 'module_instantiation')
			local parents = get_shared_parents(cursor_module, selected_module)
			local shared_scope = filter(parents,function(elem)
				return elem:type() == "module_declaration" or elem:type() == "generate_block" 
			end)
			-- Find the place in scope to have the net declaration
			-- This should be directly before the first unnamed child in a generate block
			-- Should be directly before the first data declaration or after the last port declaration
			local declaration_row
			if shared_scope[1]:type() == 'generate_block' then
				local child
				if shared_scope[1].child(0):named() then
					child = shared_scope[1]:child(1)
				else
					child = shared_scope[1]:child(0)
				end
				local sr,sc,er,ec = TS.get_node_range(child, 0) 
				declaration_row = sr
			elseif shared_scope[1]:type() == 'module_declaration' then
				local items = filter_children(shared_scope[1], function(val)
					local keywords = {
						["module_ansi_header"] = true,
						["module_nonansi_header"] = true,
						["local_parameter_declaration"] = true,
						["port_declaration"] = true,
						["data_declaration"] = true,
					}
					return keywords[val:type()]
				end)
				for idx, node in ipairs(items) do
					if node:type() == "data_declaration" then
						local sr,sc,er,ec = TS.get_node_range(node, 0) 
						declaration_row = sr
						break
					else
						local sr,sc,er,ec = TS.get_node_range(node, 0) 
						declaration_row = er + 1
					end
				end
			end
			vim.api.nvim_buf_set_lines(0, declaration_row, declaration_row, true, {declaration})
		end
	end
	-- Have user select ports to connect
	Util.telescope_ports(port_table,inst_connections, require("telescope.themes").get_dropdown{})	
end

local function setup(opt)
	local defaultOpts = { cmd = "AutoInst", fmt = false }
	autoinst = vim.tbl_extend("force", defaultOpts, opt or {})
	updateinst = vim.tbl_extend("force", {cmd = "UpdateInst", fmt = false}, opt or {})
	connectports = vim.tbl_extend("force", {cmd = "ConnectPorts", fmt = false}, opt or {})

	vim.api.nvim_create_user_command(autoinst.cmd, function(opts)
		auto_instantiation(opts.args)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command(updateinst.cmd, function(opts)
		update_instantiation()
	end, { nargs = "?" })
	vim.api.nvim_create_user_command(connectports.cmd, function(opts)
		connect_ports()
	end, { nargs = "?" })
end

return {
	setup = setup,
}
