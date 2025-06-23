local Util = require("autoinst.util")
local VTS = require("verilog_ts_util.util")
local TS = vim.treesitter
local TSU = require 'nvim-treesitter.ts_utils'


local port_keywords = {
	["ansi_port_declaration"] = true,
	["port_declaration"] = true,
}
local net_keywords = {
	["net_decl_assignment"] = true,
	["variable_decl_assignment"] = true,
}

local parameter_keywords = {
	["parameter_declaration"] = true,
}

local localparam_keywords = {
	["local_parameter_declaration"] = true,
}

local function get_unpacked_dimension(node)
	local unpacked = VTS.filter_children(node, function(val)
		return val:type() == 'unpacked_dimension'
	end)
	if unpacked == nil then
		unpacked = {}
		sibling = node:next_sibling()
		while sibling ~= nil and sibling:type() == 'unpacked dimension' do
			table.insert(unpacked,sibling)
		end
	end
	return unpacked
end

local function get_definition(module, name)
	local definitions = VTS.filter_children(cursor_module,function(val)
		local keywords = {
			["ansi_port_declaration"] = true,
			["net_decl_assignment"] = true,
			["port_declaration"] = true,
			["variable_decl_assignment"] = true,
		}
		return keywords[val:type()]
	end)
	local check_port_name = {
		["ansi_port_declaration"] = function(node)
		end,
		["net_decl_assignment"] = function(node)

		end,
		["port_declaration"] = function(node)

		end,
		["variable_decl_assignment"] = function(node)

		end,
	}
	for _,def in ipairs(definitions) do
		if check_port_name[def:type()](def)then
			return def
		end
	end
	return
end

local function create_port_from_cursor()
	-- Gets the name from the cursor position
	local cursor_node = TSU.get_node_at_cursor(0)
	cursor_node = search_parents_for_type(cursor_node, 'simple_identifier') 
	local cursor_module = VTS.search_parents_for_type(cursor_node, 'module_declaration')
	-- Checks if it already exists as a port or a net
	local definition = get_definition(cursor_module, TS.get_node_text(cursor_node,0))
	if definition then
		if port_keywords[definition:type()] then
			print("Port already exists")
			return
		elseif net_keywords[definition:type()] then

		end
	end
	-- If it's a port, return early
	-- If it's a net then remove the net
	-- Try to determine the directionality of the port
	-- Create the declaration and allow the user to modify it
	-- Insert the declaration into the proper place
end

local function create_net_from_cursor()
	-- Gets the name from the cursor position
	local cursor_node = TSU.get_node_at_cursor(0)
	cursor_node = search_parents_for_type(cursor_node, 'simple_identifier') 
	local cursor_module = VTS.search_parents_for_type(cursor_node, 'module_declaration')
	-- Checks if it already exists as a port or a net
	local definitions = VTS.filter_children(cursor_module,function(val)
		local keywords = {
			["ansi_port_declaration"] = true,
			["net_decl_assignment"] = true,
			["port_declaration"] = true,
			["variable_decl_assignment"] = true,
		}
		return keywords[val:type()]
	end)
	local get_port_name = {
		["ansi_port_declaration"] = function(node)
		end,
		["net_decl_assignment"] = function(node)

		end,
		["port_declaration"] = function(node)

		end,
		["variable_decl_assignment"] = function(node)

		end,
	}
	local port_keywords = {
		["ansi_port_declaration"] = true,
		["port_declaration"] = true,
	}
	local net_keywords = {
		["net_decl_assignment"] = true,
		["variable_decl_assignment"] = true,
	}
	local port_found = false
	local declaration = ''
	for _,def in ipairs(definitions) do
		local name = get_port_name[def:type()](def)
		if TS.get_node_text(name,0) == TS.get_node_text(cursor_node,0) and net_keywords[def:type()] then
			print("Net already declared")
			return
		--TODO need to remove prefix/suffix from port names
		elseif TS.get_node_text(name,0) == TS.get_node_text(cursor_node,0) and port_keywords[def:type()] then
			port_found = true
			-- Create declaration from port defintition
			local net_types = filter_children(def, function(val)
				local keywords = {
					["net_port_type"] = true,
					["variable_port_type"] = true,
				}
				return keywords[val:type()]
			end)
			--Add type (including packed dimension) to declaration
			if net_types == nil then
				declaration = 'wire '
			else
				declaration = TS.get_node_text(net_types[1],0)
			end
			-- Remove the prefix from the net name (TODO: make configurable)
			-- Add the name of the port to the declaration
			declaration = declaration .. string.sub(TS.get_node_text(name,0),3,-1)
			-- Find and add any unpacked dimensions to the declaration
			local unpacked = get_unpacked_dimension(name)
			for _,node in ipairs(unpacked) do
				declaration = declaration .. TS.get_node_text(node,0)
			end
			declaration = declaration .. ';'
			--Remove port definition
			remove_port_definition(cursor_module, name)
			break
		end

	end
	-- Create the declaration and allow the user to modify it
	if not port_found then
	end
	declaration = vim.fn.input("Port Declaration: ", declaration, "file")
	-- Insert the declaration into the proper place
end

local function create_parameter_from_cursor()
	-- Gets the name from the cursor position
	local cursor_node = TSU.get_node_at_cursor(0)
	cursor_node = search_parents_for_type(cursor_node, 'simple_identifier') 
	local cursor_module = VTS.search_parents_for_type(cursor_node, 'module_declaration')
	-- Checks if it already exists as a port or a net
	local definitions = VTS.filter_children(cursor_module,function(val)
		local keywords = {
			["ansi_port_declaration"] = true,
			["net_declaration"] = true,
			["port_declaration"] = true,
			["data_declaration"] = true,
		}
		return keywords[val:type()]
	end)
	--Check if (local)parameter exists
	--
end

local function create_local_parameter_from_cursor()
	-- Gets the name from the cursor position
	local cursor_node = TSU.get_node_at_cursor(0)
	cursor_node = search_parents_for_type(cursor_node, 'simple_identifier') 
	local cursor_module = VTS.search_parents_for_type(cursor_node, 'module_declaration')
	-- Checks if it already exists as a port or a net
	local definitions = VTS.filter_children(cursor_module,function(val)
		local keywords = {
			["ansi_port_declaration"] = true,
			["net_declaration"] = true,
			["port_declaration"] = true,
			["data_declaration"] = true,
		}
		return keywords[val:type()]
	end)
end


-- Features I want
-- 	* Be able to write a variable name and then run a command to declare it as logic/port
-- 	* Convert between local nets and ports and handle prefixes/suffixes for ports
-- 	* Configure how ports and parameters are auto-instantiated
-- 		* Choose between empty or auto-populating and removing pre-/suf-fix
-- 		* Automatically create parameters in current module
-- 	* Add attributes for logic elements/modules (ex. (*mark_debug="true"*))
-- 		* Probably use telescope as a picker
-- 	* Think of a way to handle constraints in the verilog source file
--

