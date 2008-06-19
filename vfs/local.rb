require 'vfs/abstract'
require 'vfs/memorylocking'

module VFS		
	class Local < Abstract
		include MemoryLocking
		
		class Properties < VFS::Properties
			def initialize(vfs, filename)
				super

				@stat = File.lstat(@filename)
			end
			
			def creationdate
				@stat.ctime
			end
			
			def lastmodified
				@stat.mtime
			end
			
			def etag
				sprintf('%x-%x-%x', @stat.ino, @stat.size, @stat.mtime.to_i)
			end
			
			def contenttype
				File.directory?(@filename) ? "httpd/unix-directory" : WEBrick::HTTPUtils::mime_type(@filename, @vfs.config[:MimeTypes])
			end
			
			def contentlength
				File.file?(@filename) or raise WEBrick::HTTPStatus::NotFound
				@stat.size
			end
		end
				
		def self.stream(filename, acc)
			File.open(filename, acc) {|f| yield f}
		end
		
		def self.set_lastmodified(filename, mtime)
			File.utime(Time.now, mtime, filename)
		end
		
		def self.directory?(filename)
			File.directory?(filename)
		end
		
		def self.mkdir(filename)
			Dir.mkdir(filename)
		end
		
		def self.remove(filename)
			FileUtils.rm_rf(filename)
		end
		
		def self.copy(src, dst, recursive=true)
			if directory?(src)
				if recursive
					FileUtils.cp_r(src, dest, {:preserve => true})
				else
					mkdir(dst)
				
					st = File.stat(src)
				
					begin
						# Make sure that the new directory has the same
						# access and modified time
						File.utime(st.atime, st.mtime, dst)
					rescue
						# simply ignore
					end
				end
			else
				FileUtils.cp(src, dst, {:preserve => true})
			end
		end
		
		def self.move(src, dst)
			File.rename(src, dst)
		end
		
		def self.exists?(filename)
			File.exists?(filename)
		end
		
		def self.filtered?(filename)
			(@config[:NondisclosureName] + @config[:NotInListName]).find do |pat|
				File.fnmatch(pat, filename)
			end
		end
		
		def self.entries(dirname)
			Dir.entries(dirname).each do |f|
				next if f == ".." || f == "."
				next if filtered?(f)
		
				yield f
			end
		end
		
		def self.properties(filename)
			Local::Properties.new(self, filename)
		end
		
		def self.parse_filename(req, res)
			res.filename = @config[:Root].dup
			path_info = req.path_info.scan(%r|/[^/]*|)

			path_info.unshift("")	# dummy for checking @root dir
			
			while base = path_info.first
				raise WEBrick::HTTPStatus::NotFound if filtered?(base)

				break if base == "/"
				break unless File.directory?(res.filename + base)
				shift_path_info(req, res, path_info)
			end

			if base = path_info.first
				raise WEBrick::HTTPStatus::NotFound if filtered?(base)

				if base == "/"
					shift_path_info(req, res, path_info)
				elsif not File.file?(res.filename + base)
					raise WEBrick::HTTPStatus::NotFound, "`#{req.path}' not found."
				else
					shift_path_info(req, res, path_info, base)
				end
			end
			
			return res.filename
		end
		
		def self.shift_path_info(req, res, path_info, base=nil)
			tmp = path_info.shift
			base = base || tmp
			req.path_info = path_info.join
			req.script_name << base
			res.filename << base
		end
	end
end
