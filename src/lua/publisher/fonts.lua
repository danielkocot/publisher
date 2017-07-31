--- Fonthandling after fontloading.
--
--  fonts.lua
--  speedata publisher
--
--  For a list of authors see `git blame'
--  See file COPYING in the root directory for license info.
--
--- Loading a font is only one part of the story. Proper dealing with fonts
--- requires post processing at various stages.

require("fonts.fontloader")
module(...,package.seeall)

local lookup_fontname_filename={}
local font_instances={}

local used_fonts={}


local att_fontfamily     = 1
local att_italic         = 2
local att_bold           = 3
local att_script         = 4

local glue_spec_node = node.id("glue_spec")
local glue_node      = node.id("glue")
local glyph_node     = node.id("glyph")
local disc_node      = node.id("disc")
local rule_node      = node.id("rule")
local kern_node      = node.id("kern")
local penalty_node   = node.id("penalty")
local whatsit_node   = node.id("whatsit")
local hlist_node     = node.id("hlist")
local vlist_node     = node.id("vlist")


--- Every font family ("text", "Chapter"), that is defined by DefineFontfamily gets an internal
--- number. This number is stored here.
lookup_fontfamily_name_number={}

--- Every font family (given by number) has variants like italic, bold etc.
--- These are stored as a table in this table.
--- The following keys are stored
---
---  * normal
---  * bolditalic
---  * italic
---  * bold
---  * baselineskip
---  * size
lookup_fontfamily_number_instance={}


function load_fontfile( name, filename,parameter_tab)
    assert(filename)
    assert(name)
    lookup_fontname_filename[name]={filename,parameter_tab or {}}
    return true
end

function table.find(tab,key)
    assert(tab)
    assert(key)
    local found
    for k_tab,v_tab in pairs(tab) do
        if type(key)=="table" then
            found = true
            for k_key,v_key in pairs(key) do
                if k_tab[k_key]~= v_key then found = false end
            end
            if found==true then
                return v_tab
            end
        end
    end
    return nil
end


-- Return false, errormessage in case of failure, true, number otherwise. number
-- is the internal font number. After calling this method, the font can be used
-- with the key { filename,size}
function make_font_instance( name,size )
    -- Name is something like "TeXGyreHeros-Regular", the visible name of the font file
    assert(name)
    assert(size)
    assert(    type(size)=="number" )
    if not lookup_fontname_filename[name] then
        local msg = string.format("Font instance '%s' is not defined!", name)
        err(msg)
        return false, msg
    end
    local filename,parameter = unpack(lookup_fontname_filename[name])
    assert(filename)
    local k = {filename = filename, size = size}
    if parameter.otfeatures then
        k.smcp = parameter.otfeatures.smcp
    end
    local fontnumber = table.find(font_instances,k)
    if fontnumber then
        return true,fontnumber
    else
        local ok,f = fonts.fontloader.define_font(filename,size,parameter)
        if ok then
            local num = font.define(f)
            font_instances[k]=num
            used_fonts[num]=f
            return true, num
        else
            err(string.format("Font '%s' could not be loaded!",filename))
            return false, f or ""
        end
    end
    return false, "Internal error"
end


--- At this time we must adjust the contents of the paragraph how we would
--- like it. For example the (sub/sup)script glyphs still have the width of
--- the regular characters and need
function pre_linebreak( head )
    local first_head = head

    while head do
        if head.id == hlist_node then -- hlist
            pre_linebreak(head.list)
            if node.has_attribute(head,att_script) then
                local sub_sup = node.has_attribute(head,att_script)
                local fam = lookup_fontfamily_number_instance[fontfamily]
                if sub_sup == 1 then
                    head.shift = fam.scriptshift
                else
                    head.shift = -fam.scriptshift
                end
                -- The hbox still has the width of the regular glyph (from Paragraph:script)
                local n = node.hpack(head.list)
                head.width = n.width
                n.list = nil
                node.free(n)
            end
        elseif head.id == vlist_node then -- vlist
            pre_linebreak(head.list)
        elseif head.id == rule_node then -- rule
        elseif head.id == disc_node then -- discretionary
            pre_linebreak(head.pre)
            pre_linebreak(head.post)
            pre_linebreak(head.replace)
        elseif head.id == whatsit_node then -- whatsit
        elseif head.id == glue_node then -- glue
            if head.subtype == 100 then -- leader
                local l = head.leader
                local wd = node.has_attribute(l,800)

                -- Set the font for the leader
                pre_linebreak(l)

                local tmpbox
                if wd == -1 then
                    tmpbox = node.hpack(l)
                else
                    -- \hbox{ 1fil, text, 1fil }
                    local l1,l2
                    l1=node.new("glue")
                    l1.spec=node.new("glue_spec")
                    l1.spec.width = 0
                    l1.spec.stretch = 65536
                    l1.spec.stretch_order = 2
                    l1.spec.shrink = 65536
                    l1.spec.shrink_order = 2
                    l2=node.copy(l1)
                    local newhead = node.insert_before(l,l,l1)

                    local endoftext = node.tail(l)
                    newhead = node.insert_after(newhead,endoftext,l2)
                    tmpbox = node.hpack(newhead,wd,"exactly")
                end
                head.leader = tmpbox

            end
            local gluespec = head.spec
            if gluespec then
                if node.has_attribute(head,att_fontfamily) then
                    local fontfamily=node.has_attribute(head,att_fontfamily)
                    -- FIXME: safety net
                    if fontfamily == 0 then fontfamily = 1 end
                    local instance = lookup_fontfamily_number_instance[fontfamily]
                    assert(instance)
                    local f
                    local italic = node.has_attribute(head,att_italic)
                    local bold   = node.has_attribute(head,att_bold)
                    if italic == 1 and bold ~= 1 then
                        f = used_fonts[instance.italic]
                    elseif italic == 1 and bold == 1 then
                        f = used_fonts[instance.bolditalic]
                    elseif bold == 1 then
                        f = used_fonts[instance.bold]
                    else
                        f = used_fonts[instance.normal]
                    end
                    if not f then f=publisher.options.defaultfont
                    end
                    if gluespec.stretch_order == 0 and gluespec.writable then
                        gluespec.width=f.parameters.space
                        gluespec.stretch=f.parameters.space_stretch
                        gluespec.shrink=f.parameters.space_shrink
                    else
                        w("gluespec: %s, subtype: %s",tostring(gluespec),tostring(head.subtype))
                    end
                end
            else
                -- FIXME: how can it be that there is no glue_spec???
                -- no glue_spec found.
                gluespec = node.new("glue_spec")
                local fontfamily=node.has_attribute(head,att_fontfamily)
                local instance = lookup_fontfamily_number_instance[fontfamily]
                local f = used_fonts[instance.normal]
                gluespec.width   = f.parameters.space
                gluespec.stretch = f.parameters.space_stretch
                gluespec.shrink  = f.parameters.space_shrink
                head.spec = gluespec
            end
        elseif head.id == kern_node then -- kern
        elseif head.id == penalty_node then -- penalty
        elseif head.id == glyph_node then -- glyph
            if node.has_attribute(head,att_fontfamily) then
                -- not local, so that we can access fontfamily later
                fontfamily=node.has_attribute(head,att_fontfamily)

                -- Last resort
                if fontfamily == 0 then fontfamily = 1 end

                local instance = lookup_fontfamily_number_instance[fontfamily]
                local italic = node.has_attribute(head,att_italic)
                local bold   = node.has_attribute(head,att_bold)

                local instancename = nil
                if italic == 1 and bold ~= 1 then
                    instancename = "italic"
                elseif italic == 1 and bold == 1 then
                    instancename = "bolditalic"
                elseif bold == 1 then
                    instancename = "bold"
                else
                    instancename = "normal"
                end

                if node.has_attribute(head,att_script) then
                    instancename = instancename .. "script"
                end

                tmp_fontnum = instance[instancename]

                if not tmp_fontnum then
                    head.font = publisher.options.defaultfontnumber
                else
                    head.font = tmp_fontnum
                end
                -- check for small caps
                local f = used_fonts[tmp_fontnum]
                if f and f.otfeatures and f.otfeatures.onum == true then
                    local glyphno,lookups
                    local glyph_lookuptable
                    if f.characters[head.char] then
                        glyphno = f.characters[head.char].index
                        lookups = f.fontloader.glyphs[glyphno].lookups
                        for _,v in ipairs(f.onum) do
                            if lookups then
                                glyph_lookuptable = lookups[v]
                                if glyph_lookuptable then
                                    if glyph_lookuptable[1].type == "substitution" then
                                        head.char=f.fontloader.lookup_codepoint_by_name[glyph_lookuptable[1].specification.variant]
                                    end
                                end
                            end
                        end
                    end -- if f.characters[head.char]
                end -- if onum

                if f and f.otfeatures and f.otfeatures.smcp == true then
                    local glyphno,lookups
                    local glyph_lookuptable
                    if f.characters[head.char] then
                        glyphno = f.characters[head.char].index
                        lookups = f.fontloader.glyphs[glyphno].lookups
                        for _,v in ipairs(f.smcp) do
                            if lookups then
                                glyph_lookuptable = lookups[v]
                                if glyph_lookuptable then
                                    if glyph_lookuptable[1].type == "substitution" then
                                        head.char=f.fontloader.lookup_codepoint_by_name[glyph_lookuptable[1].specification.variant]
                                    elseif glyph_lookuptable[1].type == "multiple" then
                                        local lastnode
                                        for i,v in ipairs(string.explode(glyph_lookuptable[1].specification.components)) do
                                            if i==1 then
                                                head.char=f.fontloader.lookup_codepoint_by_name[v]
                                            else
                                                local n = node.new("glyph")
                                                n.next = head.next
                                                n.font = tmp_fontnum
                                                n.lang = 0
                                                n.char = f.fontloader.lookup_codepoint_by_name[v]
                                                head.next = n
                                                head = n
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end -- if f.characters[head.char]
                end -- f.otfeatures.smcp == true
            end -- fontfamily?
        else
            warning("Unknown node: %q",head.id)
        end
        head = head.next
    end

    return true
end

--- Insert a horizontal rule in the nodelist that is used for underlining.
function insert_underline( parent, head, start, typ)
    local wd = node.dimensions(parent.glue_set,parent.glue_sign, parent.glue_order,start,head)
    local ht = parent.height
    local dp = parent.depth
    local dashpattern = ""

    -- wd, ht and dp are now in pdf points
    wd = wd / publisher.factor
    ht = ht / publisher.factor
    dp = dp / publisher.factor
    local rule = node.new("whatsit","pdf_literal")
    -- thickness: ht / ...
    -- downshift: dp/2
    local rule_width = math.round(ht / 13,3)

    if typ == 2 then
        -- dashed
        dashpattern = string.format("[%g] 0 d", 3 * rule_width)
    end

    local shift_down = ( dp - rule_width ) / 1.5
    rule.data = string.format("q 0 g 0 G %g w %s 0 %g m %g %g l S Q", rule_width, dashpattern, -1 * shift_down, -wd, -1 * shift_down )
    rule.mode = 0
    parent.head = node.insert_before(parent.head,head,rule)
    return rule
end

--- In the post_linebreak function we manipulate the paragraph that doesn't
--- affect it's typesetting. Underline and 'showhyphens' is done here. The
--- overall apperance of the paragraph is fixed at this time, we can only add
--- deocration now.
function post_linebreak( head, list_head)
    local atttype = nil
    local start = nil
    while head do
        if head.id == hlist_node then -- hlist
            post_linebreak(head.list,head)
        elseif head.id == vlist_node then -- vlist
            post_linebreak(head.list,head)
        elseif head.id == disc_node then -- disc
            if publisher.options.showhyphenation then
                -- Insert a small tick where the disc node is
                local n = node.new("whatsit","pdf_literal")
                n.mode = 0
                n.data = "q 0.3 w 0 2 m 0 7 l S Q"
                -- We don't assign back the list head as we assume(!?!) that
                -- hyphenation does not start right at the beginning of the list...
                node.insert_before(list_head,head,n)
            end
        elseif head.id == glue_node then -- glue
            local att_underline = node.has_attribute(head, publisher.att_underline)
            -- at rightskip we must underline (if start exists)
            if att_underline == nil or head.subtype == 9 then
                if start then
                    insert_underline(list_head, head, start,atttype)
                    start = nil
                end
            end
        elseif head.id == glyph_node then -- glyph
            local att_underline = node.has_attribute(head, publisher.att_underline)
            if att_underline and att_underline > 0 then
                if not start then
                    atttype = att_underline
                    start = head
                end
            else
                if start then
                    insert_underline(list_head, head, start, atttype)
                    start = nil
                end
            end
        end
        head = head.next
    end
    return head
end

-- fam is a number
function clone_family( fam, params )
    -- fam_tbl = {
    --   ["baselineskip"] = "789372"
    --   ["name"] = "text"
    --   ["normalscript"] = "10"
    --   ["scriptshift"] = "197343"
    --   ["scriptsize"] = "526248"
    --   ["normal"] = "9"
    --   ["size"] = "657810"
    -- },

    local fam_tbl = lookup_fontfamily_number_instance[fam]
    local newfam = {}
    for k,v in pairs(fam_tbl) do
        newfam[k] = v
    end
    newfam.name = "cloned"
    local normal = used_fonts[fam_tbl.normal]

    local ok,b = make_font_instance(newfam.fontfaceregular, params.size * newfam.size )
    if not ok then
        err(b)
        return fam
    else
        newfam.normal = b
        newfam.size = math.floor(params.size * newfam.size)
        lookup_fontfamily_number_instance[#lookup_fontfamily_number_instance + 1] = newfam
        return #lookup_fontfamily_number_instance
    end
end

