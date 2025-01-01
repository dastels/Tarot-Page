#!/usr/local/bin/ruby

require 'prawn'
require 'json'
require 'slop'

include Prawn::Measurements

def process_args
  cmdline_config = {}

  opts = Slop.parse(banner: "usage: #{$0} [options]") do |o|
    o.string '-f', '--file', 'output filename'
    o.string '-p', '--page-size', 'page size, either a standard size (eg. A4) or <width>x<height> in mm or in (eg. 9inx12in) (default A4)', default: 'LETTER'
    o.string '-o', '--orientation', 'portrait or landscape, not valid with custom widthxheight page size (default: landscape)', default: 'portrait'
    o.string '-t', '--tarot', 'the directory name of the collection of tarot card images (required)'
    o.integer '-d', '--dups', 'number of duplicates of each card (default 1)', default: 1
    o.integer '-c', '--cols', 'number of columns of cards.'
    o.integer '-r', '--rows', 'number of rows of cards'
    o.separator 'Only one of cols/rows can be specified, and one must be specified'
    o.separator ''
    o.separator 'other options:'
    o.bool '-v', '--verbose', 'show informational output', default: false
    o.on '--version', 'print the version number' do
      puts "0.0.2"
      exit
    end
    o.on '-?', '--help', 'print options' do
      puts o
      exit
    end
  end

  [:page_size, :orientation, :tarot, :cols, :rows, :dups].each do |k|
    cmdline_config[k] = opts[k] unless opts[k].nil?
  end

  return cmdline_config, opts[:file], opts[:verbose]
end

$config, output_filename, $verbose = process_args


puts $config if $verbose

if $config[:tarot].nil?
  puts "Tarot deck required"
  exit
end

# compute the page dimensions
if PDF::Core::PageGeometry::SIZES.include?($config[:page_size].upcase)
  page_size = PDF::Core::PageGeometry::SIZES[$config[:page_size].upcase]
  case $config[:orientation]
  when 'portrait'
    width_pt = page_size[0]
    height_pt = page_size[1]
  when 'landscape'
    width_pt = page_size[1]
    height_pt = page_size[0]
  else
    puts "Bad orientation: #{$config[:orientation]}"
    exit
  end
else
  matches = $config[:page_size].downcase.match(/(\d+)(in|mm)?[xX](\d+)(in|mm)?/)
  if matches.nil?
    puts "Bad page size: #{$config[:page_size]}"
    exit
  else
    width = matches[1].to_i
    width_unit = matches[2]
    height = matches[3].to_i
    height_unit = matches[4]
    puts "page size: #{width}#{width_unit} x #{height}#{height_unit}" if $verbose
    width_pt = width_unit == 'in' ? in2pt(width) : mm2pt(width)
    height_pt = height_unit == 'in' ? in2pt(height) : mm2pt(height)
  end
end

pdf = Prawn::Document.new(page_size: [width_pt, height_pt], margin: 0)
pdf.stroke_color('000000')
pdf.fill_color('000000')

card_name = "./#{$config[:tarot]}/#{$config[:tarot]}-0001.jpg"
card_image = pdf.image(card_name)
ratio = card_image.width.to_f / card_image.height.to_f

puts "Card width: #{card_image.width}, Card height: #{card_image.height}, Ratio: #{ratio}"

pdf.delete_page(0)

# compute rows & columns
if $config[:rows].nil? and $config[:cols].nil?
  puts 'Must specify one of rows or columns'
  exit
end

if !$config[:rows].nil? and !$config[:cols].nil?
  puts 'Must specify only one of rows or columns'
  exit
end


if $config[:rows].nil?
  $config[:rows] = ($config[:cols] * ratio).ceil
elsif $config[:cols].nil?
  $config[:cols] = ($config[:rows] / ratio).floor
end

puts "rows: #{$config[:rows]}, cols: #{$config[:cols]}"


cards_per_page = $config[:rows] * $config[:cols]

puts "Cards per page: #{cards_per_page}"


card_width = (width_pt / $config[:cols]).floor
card_height = (card_width / ratio).floor

cards = ((1..78).collect {|card_number| [card_number] * $config[:dups]}).flatten

cards.each_with_index do |card_number, card_index|

  card = "./%s/%s-%04d.jpg" % [$config[:tarot], $config[:tarot], card_number]

  card_on_page = card_index % cards_per_page
  r = card_on_page / $config[:cols]
  c = card_on_page % $config[:cols]

  pdf.image(card, at: [card_width * c, card_height * (r + 1)], width: card_width, height: card_height)

  if card_on_page == cards_per_page - 1 # is the page full?
    pdf.start_new_page
  end
end


# write the output file
output_file = output_filename.nil? ? "#{$config[:tarot]}-#{$config[:rows]}x#{$config[:cols]}-#{$config[:dups]}.pdf" : output_filename

puts "Writing to #{output_file}" if $verbose

pdf.render_file(output_file)
