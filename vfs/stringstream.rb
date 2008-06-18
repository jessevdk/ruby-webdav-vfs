module VFS
	class StringStream
		attr_reader :pos
		attr_reader :buffer
		
		def initialize(buffer, acc)
			@acc = acc
			@pos = 0
			
			case acc
			when /r/
				@buffer = buffer ? buffer.dup : ''
			when /w/
				@buffer = ''
			when /a/
				@buffer = buffer ? buffer.dup : ''
				@pos = @buffer.length
			end
		end
		
		def dup
			s = StringStream.new(@buffer.dup, @acc)
		end
		
		def read(num = nil)
			if eof?
				return nil if num == nil
				return ""
			end
			
			return '' if num == 0
			
			last = num == nil ? -1 : @pos + num - 1
			s = @buffer[@pos..last].dup			
			self.pos = @pos + s.length
			
			return s
		end
		
		def write(s)
			s = s.to_s
			@buffer[@pos..@pos + s.length] = s
			
			self.pos = @pos + s.length
			s.length
		end
		
		def <<(s)
			write(s)
			self
		end
		
		def pos=(newpos)
			if newpos > @buffer.length
				newpos = @buffer.length
			elsif newpos < 0
				newpos = 0
			end
		end
		
		def eof?
			return @pos >= @buffer.length
		end
		
		alias eof eof?
	end
end
