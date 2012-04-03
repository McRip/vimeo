module Vimeo
  module Advanced
    module StreamingUpload
      class Task
        attr_reader :vimeo, :oauth_consumer
        attr_reader :io, :size, :filename
        attr_reader :endpoint
        attr_reader :id, :video_id

        def initialize(vimeo, oauth_consumer, io, size, filename)
          @vimeo, @oauth_consumer = vimeo, oauth_consumer
          @io, @size, @filename = io, size, filename
        end

        # Uploads the file to Vimeo and returns the +video_id+ on success.
        def execute
          check_quota
          authorize
          upload
          raise UploadError.new, "Validation of chunks failed." unless valid?
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

          http = Net::HTTP.new(uri.host, uri.port)
          http.set_debug_output(Logger.new(Rails.root.join("log/vimeo_upload.log")))

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
          uri = URI.parse @endpoint

          http = Net::HTTP.new(uri.host, uri.port)
          http.set_debug_output(Logger.new(Rails.root.join("log/vimeo_upload.log")))

          req = Net::HTTP::Put.new uri.request_uri
          req['content-range'] = "bytes */*"
          req.content_length = 0

          res = http.request(req)

          uploaded_bytes = res['range'].split("-")[1].to_i+1

          if uploaded_bytes != size

            uri = URI.parse @endpoint

            io.seek uploaded_bytes

            http = Net::HTTP.new(uri.host, uri.port)
            http.set_debug_output(Logger.new(Rails.root.join("log/vimeo_upload.log")))

            req = Net::HTTP::Put.new uri.request_uri
            req.body_stream = io
            req.content_type = MIME::Types.of(filename)[0].to_s
            req.content_length= size
            req['content-range'] = "bytes #{uploaded_bytes}-#{size}/#{size}"

            res = http.request(req)

            raise UploadError.new, "upload incomplete: #{res.inspect}" if res.present? && res.code != "200"
          end

          return true
        end

        # Returns a hash of the sent chunks and their respective sizes.
        def sent_chunk_sizes
          Hash[chunks.map { |chunk| [chunk.id, chunk.size] }]
        end

        # Returns a of Vimeo's received chunks and their respective sizes.
        def received_chunk_sizes
          verification    = vimeo.verify_chunks(id)
          chunk_list      = verification["ticket"]["chunks"]["chunk"]
          chunk_list      = [chunk_list] unless chunk_list.is_a?(Array)
          Hash[chunk_list.map { |chunk| [chunk["id"], chunk["size"].to_i] }]
        end
      end
    end
  end
end