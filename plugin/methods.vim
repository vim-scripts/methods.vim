""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Classbrowser Menu.
"
" Purpose:  This vimscript draws a classmenue for 
"           all tags found in the actual buffer.
"           All Menues are remembered via a sessionmenue.
"           Every menu entry jumps to the specific position.
"
" Required: This is a ruby script. You need a ruby interpreter
"           compiled to vim (configure: --enable-rubyinterp)
"
" Defaults: see class VIMMenue (line 756 ff) for adjustable 
"           default values.
" 
" Author:   Matthias Veit <matthias_veit@yahoo.de>
" Date:     Juni 2001
" Version:  $Revision: 1.13 $
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""


function! s:RubyInit()
ruby << RUBYBLOCK

###########################################
# The TagReader Class
# TagReader/Parser interface
# This interface is used by the XClass to find all XEntries.
#
# If you want to add your own TagReader, simple inherit 
# from TagReader and implement the parse method.
#
# You have to register your Tagreader for a
# specific filetype (suffix).
# @see TagReaderFactory.registerReader()
class TagReader
  #parse a given filename for all entries and fill the given xclass.
  # @param the class to fill with entries
  # @param filename the absolute (fullqulified) path to a ressource
  def parse(xclass, filename)
  end
end


###########################################
# The CTags Reader Class
# implements TagReader uses ctags
class CTags < TagReader
  attr_accessor :reader
  attr_accessor :readercommand
  attr_accessor :separator
  attr_accessor :term

  @@ctags={
    #uppercase letter go first
    "class" => "Class",
    "interface" => "Interface",
    #place prototype into submenu
    "prototype" => "prototype.",
    #place field into submenu - call it attribute
    "field" => "attribute.",
    #place variable into submenu - call it attribute
    "variable" => "attribute.",
    #place member into submenu - call it attribute
    "member" => "attribute.",
    #latex names
    "label" => "Label.",
    "section" => "*",
    "subsection" => "\\ \\ \\ +",
    "subsubsection" => "\\ \\ \\ \\ \\ \\ -",
    "paragraph" => "\\ \\ \\ \\ \\ \\ \\ \\ \\ =",
    "subparagraph" => "\\ \\ \\ \\ \\ \\ \\ \\ \\ \\ \\ \\ >",
  }


  #initialize the ctags tagreader
  # @param command to start ctags (eg.: ctags --c++-types=cfgmnpstu  --java-types=cfmi) 
  # @param separator that separates columns of output (eg.: /\s+/)
  def initialize(command, separator)
    @term = "ctags_term_line"
    @separator = Regexp.new(separator)
    @readercommand = "#{command} -x --filter=yes --filter-terminator='#{@term}\n'"
  end


  #ctags names => my names
  # @param name how it ctags calls
  # @return how we it call
  def ctagsName(name)
	if (@@ctags[name].nil?)
	  return name
	else
	  return @@ctags[name]
	end
  end

  
  #read everything ctags generates from the given filename
  # @param filename the absolute path to the file to parsed
  # @result an Array of Strings read from ctags
  def readTags(filename)
    #do we have a reader running?
    if (@reader.nil?) then
      @reader = IO.popen(@readercommand, "w+")
    end
    #create result array
    result = Array.new
    @reader.write("#{filename}\n")
    @reader.flush
    flag=true
    while(flag)
      line = @reader.readline
      line.chomp!
      if (line!=@term) then
        result.push(line)
      else
        flag=false
      end
    end
    return result
  end


  #parse a given filename
  # @param the class to fill with entries
  # @param filename the absolute path to the file to parsed
  def parse(xclass, filename)
    #create uniqueness object
    unique = Hash.new
    #parse the file
    readTags(filename).each { |line|
      (name, type, line) = line.split(@separator)
      type = ctagsName(type)
      #look for overloaded names
      if (unique.has_key?(type+name))
        olcnt=2
        olcnt+=1 while (unique.has_key?(type+name+"(#{olcnt})"))
        name = "#{name}(#{olcnt})"
      end
      unique[type+name] = true
      #create XEntry
      xclass.elements.push(XEntry.new(xclass, type, name, line))
    }
  end

end



###########################################
# The TagReaderFactory Class
# repository for different kind of tag reader
# acts as a factory for TagReader objects
class TagReaderFactory
  attr :reader
  attr :default
  
  #default constructor
  def initialize()
    @reader = Hash.new()
  end

  #register a reader for some type of file
  # @param type is the suffix of a file (eg java, cpp, tex)
  # @param reader implementing class of TagReader 
  def registerReader(type, reader) 
    @reader[type] = reader
  end

  #unregister a reader for some type of file
  # @param type is the suffix of a file (eg java, cpp, tex)
  def unregisterReader(type)
    @reader.delete(type)
  end

  #sets default reader. this reader is taken, if no reader is registered for a given type
  # @param reader implementing class of TagReader 
  def setDefaultReader(reader)
    @default = reader
  end

  #returns the reader for the given type or the default reader if the type is not registered
  # @param type is the suffix of a file (eg java, cpp, tex)
  # @exception if no reader is registered and no default reader set
  def getReader(type)
    reader = @reader[type]
    if (reader.nil?) then
      if (@default.nil?) then 
        raise "no TagReader found for type #{type} and no default Reader set."
      end
      reader = @default
    end
    return reader
  end

  #singleton instance
  @@factory=TagReaderFactory.new()
  #singleton method
  def TagReaderFactory.getInstance()
    return @@factory
  end
  
end

###########################################
# The Comparable Class
#Compareable interface. Implementing classes 
# adhere to the standard compare method.
class Compareable
  #compare two objects
  # @param object1 the object to compare
  # @param object2 the object to compare
  # @return 0 if equals, -1 if o1 lesser, 1 if o1 bigger then o2
  # @return [0,-1,1] 
  def compare(object1, object2)
  end
end

###########################################
# The TypeNameSorter Class
#Sort algorithm including type and name (in that order)
class TypeNameSorter < Compareable
  def compare(o1, o2)
    result = -1
    if (o1.instance_of?(XEntry) and o2.instance_of?(XEntry)) then
      result = o1.type<=>o2.type
      if (result==0) then
        result = o1.name<=>o2.name
      end
    end
    return result
  end
end

###########################################
# The LineSorter Class
#Sort algorithm including linenumber
class LineSorter < Compareable
  def compare(o1, o2)
    result = -1
    if (o1.instance_of?(XEntry) and o2.instance_of?(XEntry)) then
      result = o1.line<=>o2.line
    end
    return result
  end
end


###########################################
# The SorterFactory Class
# repository for different kind of comare - objects
# acts as a factory for Sorter objects
class SorterFactory
  attr :sorter
  attr :default
  
  #default constructor
  def initialize()
    @sorter = Hash.new()
  end

  #register a sorter for some type of file
  # @param type is the suffix of a file (eg java, cpp, tex)
  # @param sorter implementing class of Compareable 
  def registerSorter(type, sorter) 
    @sorter[type] = sorter
  end

  #unregister a sorter for some type of file
  # @param type is the suffix of a file (eg java, cpp, tex)
  def unregisterSorter(type)
    @sorter.delete(type)
  end

  #sets default sorter. this sorter is taken, if no sorter is registered for a given type
  # @param sorter implementing class of Compareable 
  def setDefaultSorter(sorter)
    @default = sorter
  end

  #returns the sorter for the given type or the default sorter if the type is not registered
  # @param type is the suffix of a file (eg java, cpp, tex)
  # @exception if no sorter is registered and no default sorter set
  def getSorter(type)
    sorter = @sorter[type]
    if (sorter.nil?) then
      if (@default.nil?) then 
        raise "no Sorter found for type #{type} and no default sorter set."
      end
      sorter = @default
    end
    return sorter
  end

  #singleton instance
  @@factory=SorterFactory.new()
  #singleton method
  def SorterFactory.getInstance()
    return @@factory
  end
  
end

###########################################
# The XEntry Class
# Valueholder for all entry relevant stuff
class XEntry
  #name of the entry
  attr_accessor :name
  #line number of the entry
  attr_accessor :line
  #type of the entry
  attr_accessor :type
  #the xclass we belong to
  attr_accessor :xclass

  #initilize this entry
  # @param type of entry
  # @param name of entry
  # @param line of entry
  def initialize(xclass, type, name, line)
    @xclass = xclass
	@type = type
	@name = name
	@line = line.to_i
  end

  #Comparable object
  def <=>(object)
    return @xclass.getCompareable().compare(self, object)
  end
end

###########################################
# The XClass Class
# The XClass wraps a file, holds a list of XEntry-objects
# inside this file and some describing metadata.
# Each xclass has a specific type (read from the suffix of
# a filename) and a related TagReader and Sorter.
class XClass
  attr_accessor :elements       #all xentries
  attr_accessor :name           #the absolute path to the file (given in initialize) 
  attr_accessor :basename       #the filename without suffix (Class.java => Class)
  attr_accessor :filetype       #the type of the file (Class.java => java)
  attr_accessor :menu           #the menupos inside sessionclass menu (for sortorder)
  attr_accessor :typeCount      #hash that maps type (eg. method) to number of occurences
  attr			:mtime          #last update 
  attr			:reader         #the related TagReader
  attr			:sorter         #the related Sorter
 
  #standard constructor
  # @param name absolute path to a given file 
  # @param type the type of the given file (eg: java)
  def initialize(name, type=nil)
    #remember name
	@name = name
    #initialize elements
    @elements = Array.new
    #initialize typeCount
    @typeCount = Hash.new
    #extract basename and suffix of the file
	@basename, suffix = splitName(File.basename(name))
    #set filetype
    if (!type.nil?)
      @filetype = type
    else
      @filetype = suffix
    end
    #get registered reader
    @reader = TagReaderFactory.getInstance().getReader(@filetype)
    #get registered sorter
    @sorter = SorterFactory.getInstance().getSorter(@filetype)
    #no menupos
    @menu = nil
    #no update made
	@mtime=0
    #update all entries
	update()
  end
  
  #update, if file has changed
  # parse the file and read all entries
  def update()
    if (File.exist?(@name))
	  modtime = File.stat(@name).mtime
	  if(modtime!=@mtime)
        #clear all entries
        @elements.clear
        #parse for all xentries
        reader.parse(self, @name)
        #update typecount
        @typeCount.clear
        elements.each { |entry|
          num = @typeCount[entry.type]
          num = 0 if (num.nil?)
          @typeCount[entry.type] = (num+=1)
        }
        @mtime = modtime
      end
    end
  end

  #number of entries for the given type
  # @param type is a string (eg: method) that can be found by the TagReader
  # @result number of occurences of the given type
  def numberOfType(type)
    result = @typeCount[type]
    result = 0 if (result.nil?)
    return result
  end
  
  #give Entry of given line
  # @param line is the linenumber to look what matches best 
  def getEntry(line)
	found = XEntry.new(nil,nil,0)
	@elements.each{ |xentry|
      if (xentry.line<=line and xentry.line>found.line)
        found = xentry
      end
	}
	if (found.line!=0)
	  return found 
	else
	  return nil
	end
  end
    
  #splits filename in two parts delimited by a dot
  def splitName(filename) 
    index = filename.rindex('.')
    base = filename
    suffix = ""
    if (!index.nil?) then
      base = filename.slice(0, index)
      suffix = filename.slice(index+1, filename.length)
    end
    return base, suffix
  end
  
  #set the sortmethod for this class
  # @param sortmethod is a Comparable object
  def setCompareable(sortmethod)
    if (sortmethod.nil? or !sortmethod.kind_of?(Compareable))
      raise "The given sortmethod must implement the Compareable interface"
    else
      @sorter = sortmethod
    end
  end

  #gets the compareable associated with this class 
  def getCompareable
    return @sorter
  end

  #comparator to list classes in right order
  def <=>(object)
	return @basename<=>object.basename
  end
end


###########################################
# The XSession Class
# Session (static) provides ui
class XSession

  #instance variables
  @xclasses 
  @actual
  @haveClassMenu
  @classMenueEnabled
  
  #default constructor
  def initialize()
    @xclasses = Array.new
    @haveClassMenu = false
    @classMenueEnabled = true
  end

  #get XClass-object for given file (Hash replacement)
  # @param file filename of the class
  # @return XClass object of the given filename
  def getXClass(file)
	@xclasses.each{ |xclass|
	  if (xclass.name == file)
		return xclass
	  end
	}
	return nil
  end


  #returns a preamble for shortened menues
  # @param name the name of the menuentry
  def getPreamble(name)
  return case name.upcase
	when (/^[ABCD]/) 
	  "abcd."
	when (/^[EFGH]/) 
	  "efgh."
	when (/^[IJKL]/) 
	  "ijkl."
	when (/^[MNOP]/) 
	  "mnop."
	when (/^[QRST]/) 
	  "qrst."
	when (/^[UVWXYZ]/) 
	  "uvwxyz."
	else 
	  ">>>."
	end
  end


  #encodes a string that it is dispayable by a vim menu
  # vim has a special meaning for whitespace and points - they must be escaped
  # @param string the string to display in a vim menu
  def encodeString(string) 
    result = string.dup
    result.gsub!(" ","\\ ")
    result.gsub!("\\.","\\.")
    return result
  end


  #draws the menu with specified content
  # @param xclass the XClass object to be displayed
  # @param sessiononly if true,only the sessionmenue is drawed [default=false]
  def drawmenu(xclass, sessiononly=false)
    #look if we already had a menu drawed
    hideClass() if (!@actual.nil?) 
    #something to draw?
    if (xclass.elements.length > 0) 
      #draw an empty membermenu
      showClassMenu(true)
      #draw the content
      classpreamble = ""
      classpreamble = getPreamble(xclass.basename) if (@xclasses.size>VIMMenue.MaxClasses)
      xclass.elements.sort.each{ |xentry|
        preamble = ""
        preamble = getPreamble(xentry.name) if (xclass.numberOfType(xentry.type)>VIMMenue.MaxTypes)
        name = encodeString(xentry.name)
        if (not sessiononly)
          VIM::command("amenu 300 #{VIMMenue.ClassMenue}.#{xentry.type}\\ #{preamble}\\ #{name} #{xentry.line}G") 
          @actual = xclass 
        end
        VIM::command("amenu 200.#{xclass.menu} #{VIMMenue.SessionMenue}.#{classpreamble}#{xclass.basename}.#{xentry.type}\\ #{preamble}\\ #{name} :e! +#{xentry.line} #{xclass.name}<cr>")
      }
    else
      showClassMenu(false)
    end
  end

  #draws the menu with only a separator
  # @param bool if true draw the menu entry, otherwise delete the entry
  def showClassMenu(bool)
    if (bool)
      if (!@haveClassMenu)
        VIM::command("amenu .99999 #{VIMMenue.ClassMenue}.-dep3- :")
        @haveClassMenu = true
      end
    else
      if (@haveClassMenu and !VIMMenue.ShowEmptyClassMenue())
        VIM::command("silent! aunmenu #{VIMMenue.ClassMenue}")
        @haveClassMenu = false
      end
    end
  end

  #reorders to archieve alphabetical order
  def reOrder
    #hide menu
	VIM::command("silent! aunmenu #{VIMMenue.SessionMenue}")
	pos=0
    #sort all classes
    @xclasses.sort!
    #draw all classes
	@xclasses.each { |xclass|
	  pos += 10
	  xclass.menu= pos
	  drawmenu(xclass, true)
	}
  end
  
  #adds a class to the session
  # @param file the filename to add to session
  def addClass(file)
	xclass = XClass.new(file)
	@xclasses.push(xclass)
	@xclasses.sort!
	if (@xclasses.size==(VIMMenue.MaxClasses+1)) #reorder
	  reOrder
	else #look if there are spare places
	  index = @xclasses.index(xclass)
	  if (@xclasses.size == 1)
		  reOrder 
	  elsif (index == 0) #beginning
		xclass.menu = @xclasses[1].menu-1
		if xclass.menu<0
		  reOrder 
		end
	  elsif (@xclasses.last == xclass)
		xclass.menu = @xclasses[index-1].menu+10
	  else
		if (@xclasses[index-1].menu+1 == @xclasses[index+1].menu)
		  reOrder
		else
		  xclass.menu = @xclasses[index-1].menu+1
		end
	  end
	end
	drawmenu(xclass, false)
  end
  

  #removes a class from the session
  # @param the filename to delete from the session
  def removeClass(file)
	xclass = getXClass(file)
	@xclasses.delete(xclass)
	if (@xclasses.size==(VIMMenue.MaxClasses)) #reorder
	  reOrder
	elsif (@xclasses.size==(0)) #delete menu
	  VIM::command("silent! aunmenu #{VIMMenue.SessionMenue}")
	else
	  classpreamble = ""
	  classpreamble = getPreamble(xclass.name) if (@xclasses.size>VIMMenue.MaxClasses)
	  VIM::command("silent! aunmenu #{VIMMenue.SessionMenue}.#{classpreamble}#{xclass.basename}")
	end
  end


  #show menu for the given entry
  # @param file the filename to update the class for
  def showClass(file)
	xclass = getXClass(file)
	if (xclass.nil?)
	  addClass(file)
	else
      hideClass()
	  xclass.update
	  drawmenu(xclass, false)
	end
  end

  #hide menu for the given entry
  # @session if true hide from session menu too, otherwise not.
  def hideClass(sessiontoo=false)
	xclass = @actual
	if (!xclass.nil?)
      classpreamble = ""
      classpreamble = getPreamble(xclass.basename) if (@xclasses.size>VIMMenue.MaxClasses)
      xclass.elements.sort.each{ |xentry|
        preamble = ""
        preamble = getPreamble(xentry.name) if (xclass.numberOfType(xentry.type)>VIMMenue.MaxTypes)
        name = encodeString(xentry.name)
        VIM::command("aunmenu #{VIMMenue.ClassMenue}.#{xentry.type}\\ #{preamble}\\ #{name}")
        VIM::command("aunmenu #{VIMMenue.SessionMenue}.#{classpreamble}#{xclass.basename}.#{xentry.type}\\ #{preamble}\\ #{name}") if (sessiontoo)
      }
	end
    #set actual to nil
    @actual = nil
  end

  #set the sortmethod for the actual displayed class
  # @param sortmethod is a Comparable object
  def setSortMethod(sortmethod) 
    if (!@actual.nil?)
      xclass = @actual
      #hide session menu
      classpreamble = ""
      classpreamble = getPreamble(xclass.basename) if (@xclasses.size>VIMMenue.MaxClasses)
      VIM::command("aunmenu #{VIMMenue.SessionMenue}.#{classpreamble}#{xclass.basename}")
      #set compareable
      xclass.setCompareable(sortmethod)
      drawmenu(xclass, false)
    end
  end

  #actualize statusline with current entry
  # looks for the actual class and the actual position of the cursor inside
  # the class. Displays some information in the statusline
  def setStatusLine
	strentry = ""
	xclass = getXClass($curbuf.name)
	if (!xclass.nil?)
	  (row, col) = $curwin.cursor
	  entry = xclass.getEntry(row)
	  strentry = "%{'[#{entry.name}\\\ (#{entry.type})]'}".sub(/\./,"") if (!entry.nil?)
	end
	VIM.command("set statusline=%<%f%h%m%r%=#{strentry}\\\ \\\ %l,%c%V\\\ %P")
  end


  #enable StatusLine
  # @param bool if true show stausline, otherwise not.
  def enableStatusLine(bool)
    VIM.command("augroup classbrowser")
	if (bool)
	  VIM.command("autocmd! CursorHold * ruby XSession.getInstance.setStatusLine")
	  VIM.command("set updatetime=1000")
	else
	  VIM.command("autocmd! CursorHold * ")
	  VIM.command("set statusline=")
	  VIM.command("set updatetime=4000") #default=4000
	end
	VIM.command("augroup END")
  end

  #initial behaviour: show all session classes
  # sledge hammer: iterate over all buffers, draw their menu
  # useful for startup
  def sessionInit()
	0.upto(VIM::Buffer.count-1) { |x|
	  if (!VIM::Buffer[x].name.nil?)
        if (getXClass(VIM::Buffer[x].name).nil?)
		  @xclasses.push(XClass.new(VIM::Buffer[x].name))
        else
          getXClass(VIM::Buffer[x].name).update
        end
	  end
	}
	reOrder
  end


  #Singleton interface
  def XSession.getInstance
	return @@singleton
  end

  #class variables
  @@singleton = XSession.new
end


###########################################
# The VIMMenue Config-Class.
# Initialize and Configure the menu.
#
class VIMMenue
  attr_accessor :sessionMenue
  attr_accessor :classMenue
  attr_accessor :maxClasses
  attr_accessor :maxTypes
  attr_accessor :showEmptyClassMenue

  # *********************************************
  # Change the default values to fit your needs.
  # *********************************************
  def initialize 
    #the name of the session menue
    @sessionMenue="Session&Classes"
    #the name of the class menue
    @classMenue="Class&Members"
    #how many classes to show until folding (submenue)
    @maxClasses = 40
    #how many types to show until folding (submenue)
    @maxTypes = 20
    #draw classmenu - even if there are no tags [false|true]?
    showEmptyClassMenue = false

    #register parser
    #default reader is ctags ofcourse
    TagReaderFactory.getInstance().setDefaultReader(CTags.new("ctags --c++-types=cfgmnpstu  --java-types=cfmi", "\s+"))

    #for latex files we take latags
    #TagReaderFactory.getInstance().registerReader("tex", Latags.new("latags", " \\| "))

    #register sorter 
    #default is alphanumeric ascending order
    SorterFactory.getInstance().setDefaultSorter(TypeNameSorter.new())
    #for latex files display structure
    SorterFactory.getInstance().registerSorter("tex", LineSorter.new())
  end

  #getter for attribute maxTypes
  def VIMMenue.MaxTypes
    return VIMMenue.getInstance.maxTypes
  end

  #getter for attribute maxClasses
  def VIMMenue.MaxClasses
    return VIMMenue.getInstance.maxClasses
  end

  #getter for attribute classMenue
  def VIMMenue.ClassMenue
    return VIMMenue.getInstance.classMenue
  end

  #getter for attribute sessionmenue
  def VIMMenue.SessionMenue
    return VIMMenue.getInstance.sessionMenue
  end

  #getter for attribute showEmptyClassMenue
  def VIMMenue.ShowEmptyClassMenue
    return VIMMenue.getInstance.showEmptyClassMenue
  end
  
  #singleton instance
  @@menue = VIMMenue.new
  #singleton method
  def VIMMenue.getInstance
    return @@menue
  end
end

RUBYBLOCK
endfunction
	
"show current class
function! s:Update()
	if (exists("g:menu_gui_enabled"))
		ruby XSession.getInstance.showClass(VIM.evaluate("expand(\"<afile>:p\")"))
	endif
endfunction

"eval ruby code only once
function! s:InitGUI()
	let g:menu_gui_enabled = 1
	:call <SID>RubyInit()
endfunction

"new class is loaded
function! s:AddSession()
	if (exists("g:menu_gui_enabled"))
		ruby XSession.getInstance.addClass(VIM.evaluate("expand(\"<afile>:p\")"))
	endif
endfunction

"remove class from session
function! s:DeleteSession()
	if (exists("g:menu_gui_enabled"))
		ruby XSession.getInstance.removeClass(VIM.evaluate("expand(\"<afile>:p\")"))
	endif
endfunction

"sledge hammer for start
function UpdateSession()
	if (exists("g:menu_gui_enabled"))
		ruby XSession.getInstance.sessionInit()
	endif
endfunction

"enable status line
function EnableStatusline()
	if (exists("g:menu_gui_enabled"))
		ruby XSession.getInstance.enableStatusLine(true)
	endif
endfunction

"disable status line
function DisableStatusline()
	if (exists("g:menu_gui_enabled"))
		ruby XSession.getInstance.enableStatusLine(false)
	endif
endfunction

"set name of classmenue
function SetClassmenueName(name)
	if (exists("g:menu_gui_enabled"))
      ruby << RUBYBLOCK
      XSession.getInstance.hideClass()
	  VIM::command("silent! aunmenu #{VIMMenue.ClassMenue}")
      VIMMenue.getInstance.classMenue = VIM.evaluate("a:name")
      XSession.getInstance.showClass(VIM.evaluate("expand(\"%:p\")"))
RUBYBLOCK
	endif
endfunction

"set name of sessionmenue
function SetSessionmenueName(name)
	if (exists("g:menu_gui_enabled"))
      ruby << RUBYBLOCK
	  VIM::command("silent! aunmenu #{VIMMenue.SessionMenue}")
      VIMMenue.getInstance.sessionMenue = VIM.evaluate("a:name")
      XSession.getInstance.sessionInit()
      XSession.getInstance.showClass(VIM.evaluate("expand(\"%:p\")"))
RUBYBLOCK
	endif
endfunction

"set number of class-entries  until folding
function SetClassmenueEntries(count)
	if (exists("g:menu_gui_enabled"))
      ruby << RUBYBLOCK
      XSession.getInstance.hideClass()
      VIMMenue.getInstance.maxTypes = VIM.evaluate("a:count").to_i
      XSession.getInstance.sessionInit()
      XSession.getInstance.showClass(VIM.evaluate("expand(\"%:p\")"))
RUBYBLOCK
	endif
endfunction

"set number of classes until folding
function SetSessionmenueEntries(count)
	if (exists("g:menu_gui_enabled"))
      ruby << RUBYBLOCK
      VIMMenue.getInstance.maxClasses = VIM.evaluate("a:count").to_i
      XSession.getInstance.sessionInit()
RUBYBLOCK
	endif
endfunction

"set actual class to sort alpanumerical
function SetAlphanumericsort()
	if (exists("g:menu_gui_enabled"))
      ruby XSession.getInstance.setSortMethod(TypeNameSorter.new)
    endif
endfunction

"set actual class to sort by linenumber
function SetLinesort()
	if (exists("g:menu_gui_enabled"))
      ruby XSession.getInstance.setSortMethod(LineSorter.new)
    endif
endfunction

"set autocommands
augroup classbrowser
	autocmd GUIEnter * call <SID>InitGUI()
	autocmd GUIEnter * call UpdateSession()
	autocmd BufEnter * call <SID>Update()
	autocmd BufAdd * call <SID>AddSession()
	autocmd BufWritePost * call <SID>Update()
	autocmd BufDelete * call <SID>DeleteSession()
augroup END
