#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'tmpdir'
require 'open3'
require 'fileutils'

module DirSpritePack
  Sprite = Struct.new(:name, :path, :w, :h, :x, :y, :repeat_x)

  module_function

  def parse_options(argv)
    options = {
      out_dir: '.',
      output_base: 'sprites',
      max_width: 2048,
      padding: 2,
      quality: 90,
      extensions: %w[.png .jpg .jpeg .webp]
    }

    parser = OptionParser.new do |opts|
      opts.banner = 'Usage: ruby promobu/dir_sprite_pack.rb SPRITES_DIR [options]'

      opts.on('--out-dir DIR', 'Output directory (default: current directory)') { |v| options[:out_dir] = v }
      opts.on('--output-base NAME', 'Base output name for NAME.webp and NAME.json') { |v| options[:output_base] = v }
      opts.on('--max-width PIXELS', Integer, 'Max atlas width before wrapping rows (default: 2048)') { |v| options[:max_width] = v }
      opts.on('--padding PIXELS', Integer, 'Padding between sprites in atlas (default: 2)') { |v| options[:padding] = v }
      opts.on('--quality VALUE', Integer, 'WebP quality 0-100 (default: 90)') { |v| options[:quality] = v }
      opts.on('--ext LIST', 'Comma-separated extensions (default: .png,.jpg,.jpeg,.webp)') do |v|
        options[:extensions] = v.split(',').map { |e| e.strip.downcase }.reject(&:empty?)
      end
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

    options[:sprites_dir] = argv[0]
    options
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
    out, err, status = Open3.capture3(*args)
    return out if status.success?

    abort "Command failed: #{args.join(' ')}\n#{err}"
  end

  def parse_sprite_name(raw_name, fallback_index)
    repeat_x = raw_name.match?(/(^|[-_])repeat[-_]?x($|[-_])/i)

    cleaned_name = raw_name.gsub(/(^|[-_])repeat[-_]?x($|[-_])/i, '\\1\\2')
    cleaned_name = cleaned_name.gsub(/[-_]{2,}/, '-')
    cleaned_name = cleaned_name.gsub(/\A[-_]+|[-_]+\z/, '')
    cleaned_name = "sprite_#{fallback_index}" if cleaned_name.empty?

    [cleaned_name, repeat_x]
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

  def collect_sprites(sprites_dir, extensions, magick_bin)
    ext_set = extensions.map { |e| e.start_with?('.') ? e : ".#{e}" }.map(&:downcase)
    files = Dir.children(sprites_dir)
               .map { |name| File.join(sprites_dir, name) }
               .select { |path| File.file?(path) }
               .select { |path| ext_set.include?(File.extname(path).downcase) }
               .sort

    abort "No sprite files found in #{sprites_dir}" if files.empty?

    used_names = {}

    files.each_with_index.map do |path, idx|
      base = File.basename(path, '.*')
      parsed_name, repeat_x = parse_sprite_name(base, idx + 1)
      name = unique_name(parsed_name, used_names)

      size = run_cmd(magick_bin, 'identify', '-format', '%w %h', path).strip
      w_str, h_str = size.split
      w = Integer(w_str)
      h = Integer(h_str)

      Sprite.new(name, path, w, h, nil, nil, repeat_x)
    end
  end

  def pack_sprites!(sprites, max_width, padding)
    x = 0
    y = 0
    row_h = 0
    used_w = 0

    sprites.each do |sprite|
      if sprite.w > max_width
        abort "Sprite '#{sprite.name}' width #{sprite.w}px exceeds --max-width #{max_width}px"
      end

      if x.positive? && x + sprite.w > max_width
        y += row_h + padding
        x = 0
        row_h = 0
      end

      sprite.x = x
      sprite.y = y

      x += sprite.w + padding
      used_w = [used_w, x - padding].max
      row_h = [row_h, sprite.h].max
    end

    atlas_w = [used_w, 1].max
    atlas_h = [y + row_h, 1].max
    [atlas_w, atlas_h]
  end

  def build_atlas(magick_bin, sprites, atlas_w, atlas_h, output_webp, quality)
    Dir.mktmpdir('dir_sprite_pack') do |tmpdir|
      atlas_webp = File.join(tmpdir, 'atlas.webp')
      run_cmd(
        magick_bin,
        '-size', "#{atlas_w}x#{atlas_h}",
        'xc:none',
        atlas_webp
      )

      current_canvas = atlas_webp

      sprites.each_with_index do |sprite, i|
        composed_webp = File.join(tmpdir, "atlas_#{i}.webp")
        run_cmd(
          magick_bin,
          'composite',
          '-compose', 'Over',
          '-geometry',
          "+#{sprite.x}+#{sprite.y}",
          sprite.path,
          current_canvas,
          composed_webp
        )

        current_canvas = composed_webp
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
        x: sprite.x,
        y: sprite.y,
        w: sprite.w,
        h: sprite.h,
        repeat_x: sprite.repeat_x
      }
    end

    File.write(path, JSON.pretty_generate(payload))
  end

  def run(argv)
    options = parse_options(argv)

    unless options[:padding] >= 0
      abort '--padding must be >= 0'
    end
    unless options[:max_width] > 0
      abort '--max-width must be > 0'
    end
    unless options[:quality].between?(0, 100)
      abort '--quality must be between 0 and 100'
    end

    sprites_dir = Pathname.new(options[:sprites_dir]).expand_path
    abort "Sprites directory not found: #{sprites_dir}" unless sprites_dir.directory?

    out_dir = Pathname.new(options[:out_dir]).expand_path
    FileUtils.mkdir_p(out_dir)

    output_webp = out_dir.join("#{options[:output_base]}.webp")
    output_json = out_dir.join("#{options[:output_base]}.json")

    magick_bin = find_magick
    abort 'ImageMagick not found. Install `magick` or set MAGICK_BIN=/path/to/magick.' if magick_bin.nil?

    sprites = collect_sprites(sprites_dir.to_s, options[:extensions], magick_bin)
    atlas_w, atlas_h = pack_sprites!(sprites, options[:max_width], options[:padding])

    build_atlas(magick_bin, sprites, atlas_w, atlas_h, output_webp.to_s, options[:quality])
    write_metadata(output_json.to_s, sprites)

    puts "Wrote #{output_webp}"
    puts "Wrote #{output_json}"
    puts "Sprites: #{sprites.length}"
    puts "Output size: #{atlas_w}x#{atlas_h}"
  end
end

DirSpritePack.run(ARGV) if $PROGRAM_NAME == __FILE__
