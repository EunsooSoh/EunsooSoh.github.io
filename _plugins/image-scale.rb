# frozen_string_literal: true
#
# Scale images to a percentage of their original size.
#
#   ![alt](/assets/img/posts/foo/image.png){: .s70 }
#
# `.sNN` (1 <= NN <= 100) makes the plugin read the image's pixel size from the
# source tree and add `width` / `height` attributes at NN% of it. It runs right
# after Markdown is converted, so Chirpy's refactor-content sees the same HTML as
# if the attributes had been written by hand.
#
# Never fails the build: when an image can't be resolved or measured, it logs a
# warning and leaves the <img> untouched. Explicit width/height always win.

module ImageScale
  CLASS_RE = /\As(\d{1,3})\z/.freeze
  IMG_RE = /<img\b[^>]*>/.freeze
  ATTR_RE = /([\w:-]+)="([^"]*)"/.freeze

  @cache = {}

  class << self
    def process(doc)
      html = doc.content
      return unless html&.include?('<img')

      doc.content = html.gsub(IMG_RE) { |tag| scale_tag(tag, doc) }
    end

    private

    def scale_tag(tag, doc)
      attrs = tag.scan(ATTR_RE).to_h
      percent = scale_percent(attrs['class'])
      return tag unless percent
      return tag if attrs.key?('width') || attrs.key?('height')

      src = attrs['src']
      if src.to_s.include?(':')
        warn_for(doc, "external image '#{src}' can't be measured; set width/height by hand")
        return tag
      end

      path = resolve(src, doc)
      unless path
        warn_for(doc, "cannot locate image '#{src}'")
        return tag
      end

      size = dimensions(path)
      unless size
        warn_for(doc, "cannot read size of '#{src}' (supported: png, jpg, gif, webp)")
        return tag
      end

      width = [(size[0] * percent / 100.0).round, 1].max
      height = [(size[1] * percent / 100.0).round, 1].max
      tag.sub(%r{\s*/?>\z}) { |close| %( width="#{width}" height="#{height}") + close }
    end

    def scale_percent(class_attr)
      return unless class_attr

      class_attr.split.each do |c|
        m = CLASS_RE.match(c)
        next unless m

        n = m[1].to_i
        return n if n.between?(1, 100)
      end
      nil
    end

    # Mirrors Chirpy's _includes/media-url.html: URLs containing ':' are external,
    # and `media_subpath` is always prepended (even to paths starting with '/').
    def resolve(src, doc)
      return if src.nil? || src.empty? || src.include?(':')

      rel = src.split(/[?#]/, 2).first
      rel = rel.gsub(/%\h\h/) { |m| m[1..].hex.chr }.force_encoding(Encoding::UTF_8)
      rel = File.join('/', doc.data['media_subpath'].to_s, rel)

      source = File.expand_path(doc.site.source)
      path = File.expand_path(File.join(source, rel))
      return unless path.start_with?("#{source}/") && File.file?(path)

      path
    end

    def dimensions(path)
      key = [path, File.mtime(path).to_i]
      return @cache[key] if @cache.key?(key)

      @cache[key] = File.open(path, 'rb') { |f| read_size(f) }
    rescue StandardError
      nil
    end

    def read_size(io)
      head = io.read(30).to_s.b
      if head.start_with?("\x89PNG\r\n\x1A\n".b)
        head[16, 8].unpack('NN')
      elsif head.start_with?('GIF8')
        head[6, 4].unpack('vv')
      elsif head.start_with?("\xFF\xD8".b)
        io.seek(2)
        jpeg_size(io)
      elsif head.start_with?('RIFF') && head[8, 4] == 'WEBP'
        webp_size(head)
      end
    end

    def jpeg_size(io)
      loop do
        byte = io.readbyte
        next unless byte == 0xFF

        marker = io.readbyte
        marker = io.readbyte while marker == 0xFF
        next if marker == 0x01 || marker.between?(0xD0, 0xD9)

        length = io.read(2).unpack1('n')
        # SOF0-SOF15, excluding DHT (C4), JPG (C8) and DAC (CC)
        if marker.between?(0xC0, 0xCF) && ![0xC4, 0xC8, 0xCC].include?(marker)
          height, width = io.read(5).unpack('xnn')
          return [width, height]
        end
        io.seek(length - 2, IO::SEEK_CUR)
      end
    rescue EOFError, NoMethodError
      nil
    end

    def webp_size(head)
      case head[12, 4]
      when 'VP8 '
        w, h = head[26, 4].unpack('vv')
        [w & 0x3FFF, h & 0x3FFF]
      when 'VP8L'
        b = head[21, 4].unpack1('V')
        [(b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1]
      when 'VP8X'
        w = "#{head[24, 3]}\x00".b.unpack1('V')
        h = "#{head[27, 3]}\x00".b.unpack1('V')
        [w + 1, h + 1]
      end
    end

    def warn_for(doc, message)
      Jekyll.logger.warn 'ImageScale:', "#{message} in #{doc.relative_path}"
    end
  end
end

Jekyll::Hooks.register [:documents, :pages], :post_convert do |doc|
  ImageScale.process(doc)
end
