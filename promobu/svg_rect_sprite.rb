#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'rexml/document'
require 'tmpdir'
require 'open3'
require 'fileutils'

module SvgRectSprite
  Sprite = Struct.new(:name, :source_x, :source_y, :source_w, :source_h, :atlas_x, :atlas_y, :repeat_x)

  module_function

  def parse_options(argv)
    options = {
      out_dir: '.',
      quality: 90,
      source_image: nil,
      output_base: nil
    }

    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: ruby promobu/svg_rect_sprite.rb INPUT.svg [options]'

      opts.on('--out-dir DIR', 'Output directory (default: current directory)') { |v| options[:out_dir] = v }
      opts.on('--output-base NAME', 'Base output name for NAME.webp and NAME.json') { |v| options[:output_base] = v }
      opts.on('--source-image PATH', 'Override source image path from <image href>') { |v| options[:source_image] = v }
      opts.on('--quality VALUE', Integer, 'WebP quality 0-100 (default: 90)') { |v| options[:quality] = v }
      opts.on('-h', '--help', 'Show this help') do
        puts opts
        exit 0
      end
    end

    parser.parse!(argv)

    if argv.empty?
      warn parser.to_s
      exit 1
    end

    options[:input_svg] = argv[0]
    options
  end

  def read_svg(svg_path)
    xml = File.read(svg_path)
    REXML::Document.new(xml)
  rescue Errno::ENOENT
    abort "Input SVG not found: #{svg_path}"
  rescue REXML::ParseException => e
    abort "Failed to parse SVG #{svg_path}: #{e.message}"
  end

  def find_source_image_href(document)
    image = REXML::XPath.first(document, "//*[local-name()='image']")
    return nil unless image

    image.attributes['href'] || image.attributes['xlink:href']
  end

  def parse_rectangles(document)
    sprites = []
    used_names = {}

    REXML::XPath.each(document, "//*[local-name()='rect']") do |rect|
      x = float_attr(rect, 'x', 0.0)
      y = float_attr(rect, 'y', 0.0)
      w = float_attr(rect, 'width', nil)
      h = float_attr(rect, 'height', nil)

      next if w.nil? || h.nil?

      sx = x.floor
      sy = y.floor
      sw = [(x + w).ceil - sx, 1].max
      sh = [(y + h).ceil - sy, 1].max

      raw_name = rect.attributes['id'] || "sprite_#{sprites.length + 1}"
      name, repeat_x = parse_sprite_id(raw_name, sprites.length + 1)
      name = unique_name(name, used_names)

      sprites << Sprite.new(name, sx, sy, sw, sh, nil, nil, repeat_x)
    end

    sprites
  end

  def parse_sprite_id(raw_name, fallback_index)
    repeat_x = raw_name.match?(/(^|[-_])repeat[-_]?x($|[-_])/i)

    cleaned_name = raw_name.gsub(/(^|[-_])repeat[-_]?x($|[-_])/i, '\1\2')
    cleaned_name = cleaned_name.gsub(/[-_]{2,}/, '-')
    cleaned_name = cleaned_name.gsub(/\A[-_]+|[-_]+\z/, '')
    cleaned_name = "sprite_#{fallback_index}" if cleaned_name.empty?

    [cleaned_name, repeat_x]
  end

  def parse_svg_canvas_size(document)
    root = document.root
    return nil if root.nil?

    width = parse_length(root.attributes['width'])
    height = parse_length(root.attributes['height'])
    return [width.ceil, height.ceil] if width && height

    view_box = root.attributes['viewBox']
    return nil if view_box.nil?

    parts = view_box.split(/[\s,]+/).map { |v| Float(v) rescue nil }
    return nil if parts.length < 4 || parts[2].nil? || parts[3].nil?

    [parts[2].ceil, parts[3].ceil]
  end

  def parse_length(value)
    return nil if value.nil?

    match = value.to_s.strip.match(/\A(-?\d+(?:\.\d+)?)/)
    return nil unless match

    Float(match[1])
  rescue ArgumentError
    nil
  end

  def float_attr(node, key, fallback)
    value = node.attributes[key]
    return fallback if value.nil?

    Float(value)
  rescue ArgumentError
    fallback
  end

  def unique_name(name, used_names)
    return used_names[name] = name unless used_names.key?(name)

    index = 2
    loop do
      candidate = "#{name}_#{index}"
      unless used_names.key?(candidate)
        used_names[candidate] = candidate
        return candidate
      end
      index += 1
    end
  end

  def keep_original_coordinates!(sprites)
    sprites.each do |sprite|
      sprite.atlas_x = sprite.source_x
      sprite.atlas_y = sprite.source_y
    end
  end

  def find_magick
    explicit = ENV['MAGICK_BIN']
    return explicit if explicit && File.executable?(explicit)

    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |path|
      magick = File.join(path, 'magick')
      return magick if File.executable?(magick)

      convert = File.join(path, 'convert')
      return convert if File.executable?(convert)
    end

    nil
  end

  def run_cmd(*args)
    _out, err, status = Open3.capture3(*args)
    return if status.success?

    abort "Command failed: #{args.join(' ')}\n#{err}"
  end

  def build_atlas(magick_bin, source_image, sprites, atlas_w, atlas_h, output_webp, quality)
    Dir.mktmpdir('svg_rect_sprite') do |tmpdir|
      atlas_png = File.join(tmpdir, 'atlas.png')
      run_cmd(
        magick_bin,
        '-size', "#{atlas_w}x#{atlas_h}",
        'xc:none',
        atlas_png
      )

      current_canvas = atlas_png

      sprites.each_with_index do |sprite, i|
        crop_png = File.join(tmpdir, "crop_#{i}.png")
        run_cmd(
          magick_bin,
          source_image,
          '-crop',
          "#{sprite.source_w}x#{sprite.source_h}+#{sprite.source_x}+#{sprite.source_y}",
          '+repage',
          crop_png
        )

        composed_png = File.join(tmpdir, "atlas_#{i}.png")
        run_cmd(
          magick_bin,
          'composite',
          '-compose', 'Over',
          '-geometry',
          "+#{sprite.atlas_x}+#{sprite.atlas_y}",
          crop_png,
          current_canvas,
          composed_png
        )

        current_canvas = composed_png
      end

      run_cmd(
        magick_bin,
        current_canvas,
        '-quality', quality.to_s,
        output_webp
      )
    end
  end

  def write_metadata(path, sprites)
    payload = {}

    sprites.each do |sprite|
      payload[sprite.name] = {
        x: sprite.atlas_x,
        y: sprite.atlas_y,
        w: sprite.source_w,
        h: sprite.source_h,
        repeat_x: sprite.repeat_x
      }
    end

    File.write(path, JSON.pretty_generate(payload))
  end

  def run(argv)
    options = parse_options(argv)

    unless options[:quality].between?(0, 100)
      abort '--quality must be between 0 and 100'
    end

    input_svg = Pathname.new(options[:input_svg]).expand_path
    document = read_svg(input_svg)

    href = options[:source_image] || find_source_image_href(document)
    abort 'No <image href="..."> found in SVG. Use --source-image PATH.' if href.nil? || href.strip.empty?
    abort 'Data URI images are not supported; use an external image file.' if href.start_with?('data:')

    source_image = Pathname.new(href)
    source_image = input_svg.dirname.join(source_image) unless source_image.absolute?
    source_image = source_image.cleanpath

    unless source_image.exist?
      abort "Source image not found: #{source_image}"
    end

    sprites = parse_rectangles(document)
    abort 'No <rect> elements with width/height found in SVG.' if sprites.empty?

    canvas_size = parse_svg_canvas_size(document)
    abort 'Cannot determine SVG canvas size; set width/height or viewBox in the SVG.' if canvas_size.nil?
    atlas_w, atlas_h = canvas_size

    keep_original_coordinates!(sprites)

    out_of_bounds = sprites.find do |sprite|
      sprite.atlas_x.negative? || sprite.atlas_y.negative? ||
        sprite.atlas_x + sprite.source_w > atlas_w ||
        sprite.atlas_y + sprite.source_h > atlas_h
    end
    if out_of_bounds
      abort "Sprite '#{out_of_bounds.name}' is outside SVG canvas #{atlas_w}x#{atlas_h}."
    end

    out_dir = Pathname.new(options[:out_dir]).expand_path
    FileUtils.mkdir_p(out_dir)

    default_base = input_svg.basename.sub_ext('').to_s
    output_base = options[:output_base] || default_base
    output_webp = out_dir.join("#{output_base}.webp")
    output_json = out_dir.join("#{output_base}.json")

    magick_bin = find_magick
    abort 'ImageMagick not found. Install `magick` or set MAGICK_BIN=/path/to/magick.' if magick_bin.nil?

    build_atlas(magick_bin, source_image.to_s, sprites, atlas_w, atlas_h, output_webp.to_s, options[:quality])
    write_metadata(output_json.to_s, sprites)

    puts "Wrote #{output_webp}"
    puts "Wrote #{output_json}"
    puts "Sprites: #{sprites.length}"
    puts "Output size: #{atlas_w}x#{atlas_h}"
  end
end

SvgRectSprite.run(ARGV) if $PROGRAM_NAME == __FILE__
