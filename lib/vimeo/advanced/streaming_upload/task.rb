module Vimeo
  module Advanced
    module StreamingUpload
      class Task
        attr_reader :vimeo, :oauth_consumer
        attr_reader :io, :size, :filename
        attr_reader :endpoint
        attr_reader :id, :video_id
        attr_reader :uploaded_bytes

        def initialize(vimeo, oauth_consumer, io, size, filename)
          @vimeo, @oauth_consumer = vimeo, oauth_consumer
          @io, @size, @filename = io, size, filename
        end

        # Uploads the file to Vimeo and returns the +video_id+ on success.
        def execute
          check_quota
          repeats = 0
          begin
            authorize
            upload
            repeats = repeats+1
          end until valid? || repeats >= 15
          raise UploadError.new, "Upload repeat limit reached." if repeats >= 15
          complete

          return video_id
        end

        protected

        # Checks whether the file can be uploaded.
        def check_quota
          quota = vimeo.get_quota
          free  = quota["user"]["upload_space"]["free"].to_i

          raise UploadError.new, "file size exceeds quota. required: #{size}, free: #{free}" if size > free
        end

        # Gets a +ticket_id+ for the upload.
        def authorize
          ticket = vimeo.get_ticket :upload_method => "streaming"

          @id             = ticket["ticket"]["id"]
          @endpoint       = ticket["ticket"]["endpoint"]
          max_file_size   = ticket["ticket"]["max_file_size"].to_i

          raise UploadError.new, "file was too big: #{size}, maximum: #{max_file_size}" if size > max_file_size
        end

        # Performs the upload.
        def upload
          uri = URI.parse @endpoint
          io.rewind

          http = Net::HTTP.new(uri.host, uri.port)

          req = Net::HTTP::Put.new uri.request_uri
          req.body_stream = io
          req.content_type = MIME::Types.of(filename)[0].to_s
          req.content_length= size

          res = http.request(req)
        end

        # Tells vimeo that the upload is complete.
        def complete
          @video_id = vimeo.complete(id, filename)
        end

        # Compares Vimeo's chunk list with own chunk list. Returns +true+ if identical.
        def valid?

          validate

          #raise UploadError.new, "upload total incomplete: size #{@size}, :uploaded: #{@uploaded_bytes}" if @uploaded_bytes+8 < @size

          return (@uploaded_bytes+1) == @size
          #  begin
          #    reupload
          #  rescue Timeout::Error
          #    validate
          #    return true if (@uploaded_bytes+1) == @size
          #    raise UploadError.new, "upload incomplete: size #{@size}, :uploaded: #{@uploaded_bytes+1}"
          #  end
          #end

         # return true
        end

        #def reupload
        #  uri = URI.parse @endpoint
        #
        #  @io.seek @uploaded_bytes
        #
        #  http = Net::HTTP.new(uri.host, uri.port)
        #  http.set_debug_output(Logger.new(Rails.root.join("log/vimeo_upload.log")))
        #
        #  req = Net::HTTP::Put.new uri.request_uri
        #  req.body_stream = @io
        #  req.content_type = MIME::Types.of(filename)[0].to_s
        #  req.content_length= @size
        #  req['content-range'] = "bytes #{@uploaded_bytes+1}-#{@size-1}/#{@size}"
        #
        #  res = http.request(req)
        #end

        def validate
          uri = URI.parse @endpoint

          http = Net::HTTP.new(uri.host, uri.port)
          #http.set_debug_output(Logger.new(Rails.root.join("log/vimeo_upload.log")))

          req = Net::HTTP::Put.new uri.request_uri
          req['content-range'] = "bytes */*"
          req.content_length = 0

          res = http.request(req)

          @uploaded_bytes = res['range'].split("-")[1].to_i
        end
      end
    end
  end
end