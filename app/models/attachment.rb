class Attachment < DBModel
  belongs_to :note
  belongs_to :contact
  has_one :blob,
    :class_name => "AttachmentBlob",
    :dependent => :destroy

  TYPES = {
    :image => "image/jpeg",
    :jpeg => "image/jpeg",
    :png => "image/png",
    :gif => "image/gif",
    :video => "video/mp4",
  }

  MAX_SIZE = 300

  def self.build_from_url(url)
    a = Attachment.new
    a.source = url

    s = ActivityStream.sponge
    a.build_blob
    a.blob.data = s.get(url)

    res = s.last_response
    a.type = res["Content-Type"] || res["Content-type"] || res["content-type"]

    if a.image?
      begin
        reader, writer = IO.pipe("binary", :binmode => true)
        writer.set_encoding("binary")

        pid = fork do
          reader.close

          # lock down
          Pledge.pledge("stdio")

          input = GD2::Image.load(a.blob.data).to_true_color

          if input.width == 0 || input.height == 0
            raise "invalid size #{input.width}x#{input.height}"
          end

          writer.write([ input.width, input.height ].pack("LL"))

          # TODO: strip EXIF

#          if input.width < MIN_WIDTH || input.height < MIN_HEIGHT ||
#          input.width > MAX_WIDTH || input.height > MAX_HEIGHT
#            # don't write anything else, the reader will error nicely
#          else
#            final = GD2::Image::TrueColor.new(input.width, input.height)
#            final.alpha_blending = false
#            final.save_alpha = false
#            final.copy_from(input, 0, 0, 0, 0, input.width, input.height)
#
#            writer.write(final.png(9))
#          end

          writer.close
          exit!(0) # skips exit handlers
        end

        writer.close

        result = "".encode("binary")
        while !reader.eof?
          result << reader.read(1024)
        end
        reader.close

        Process.wait(pid)

      rescue Errno::EPIPE
        STDERR.puts "got EPIPE forking image converter"
      end

      #self.width, self.height, data = result.to_s.unpack("LLa*")
      a.width, a.height = result.to_s.unpack("LL")
    end
    a
  end

  def activitystream_object
    {
      "type" => "Document",
      "mediaType" => self.type,
      "url" => "#{App.base_url}/attachments/#{self.id}",
      "width" => self.width,
      "height" => self.height,
    }
  end

  def html
    if image?
      "<a href=\"#{App.base_url}/attachments/#{id}\">" <<
        "<img src=\"#{App.base_url}/attachments/#{id}\" " <<
        "intrinsicsize=\"#{self.width}x#{self.height}\"></a>"
    elsif video?
      "<video controls=1 preload=metadata " <<
        "intrinsicsize=\"#{self.width}x#{self.height}\">\n" <<
        "<source src=\"#{App.base_url}/attachments/#{id}\" " <<
        "type=\"#{self.type}\" />\n" <<
        "Your browser doesn't seem to support HTML video. " <<
        "You can <a href=\"#{App.base_url}/attachments/#{id}\">" <<
        "download the video</a> instead.\n" <<
      "</video>"
    else
      "#{self.type}?"
    end
  end

  def image?
    [ TYPES[:jpeg], TYPES[:png], TYPES[:gif] ].include?(self.type)
  end

  def video?
    self.type == TYPES[:video]
  end
end
