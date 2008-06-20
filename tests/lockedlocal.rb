require 'vfs/local'
require 'memorylocking'
		
class LockedLocal < VFS::Local
	include MemoryLocking
end
