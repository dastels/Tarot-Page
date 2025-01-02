#!/usr/local/bin/ruby

require 'prawn'
require 'json'
require 'slop'

include Prawn::Measurements

def process_args
  cmdline_config = {}

  opts = Slop.parse(banner: "usage: #{$0} [options]") do |o|
    o.string '--dir', 'output directory (default: current directory)', default: ''
    o.string '-f', '--file', 'output filename'
    o.string '-p', '--page-size', 'page size, either a standard size (eg. A4) or <width>x<height> in mm or in (eg. 9inx12in) (default A4)', default: 'LETTER'
    o.string '-o', '--orientation', 'portrait or landscape, not valid with custom widthxheight page size (default landscape)', default: 'portrait'
    o.string '-t', '--tarot', 'the directory name of the collection of tarot card images (required)'
    o.integer '-d', '--dups', 'number of duplicates of each card (default 1)', default: 1
    o.integer '-c', '--cols', 'number of columns of cards.'
    o.integer '-r', '--rows', 'number of rows of cards'
    o.string '-w', '--width', 'width of cards: in or mm'
    o.string '-h', '--height', 'height of cards: in or mm'
    o.separator 'Only one of cols/rows/width/height can be specified, and one must be specified'
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

  return opts
end

$config = process_args

def make_image_name(deck, card_number)
  "./%s_images/%s-%04d.jpg" % [deck, deck, card_number]
end


if $config[:tarot].nil?
  puts "Tarot deck required"
  exit
end

# compute the page dimensions
if PDF::Core::PageGeometry::SIZES.include?($config[:page_size].upcase)
  page_size = PDF::Core::PageGeometry::SIZES[$config[:page_size].upcase]
  case $config[:orientation]
  when 'portrait'
    page_width_pt = page_size[0]
    page_height_pt = page_size[1]
  when 'landscape'
    page_width_pt = page_size[1]
    page_height_pt = page_size[0]
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
    puts "page size: #{width}#{width_unit} x #{height}#{height_unit}" if $config[:verbose]
    page_width_pt = width_unit == 'in' ? in2pt(width) : mm2pt(width)
    page_height_pt = height_unit == 'in' ? in2pt(height) : mm2pt(height)
  end
end

puts "Page size: #{page_width_pt}x#{page_height_pt}" if $config[:verbose]
pdf = Prawn::Document.new(page_size: [page_width_pt, page_height_pt], margin: 0)
pdf.stroke_color('000000')
pdf.fill_color('000000')

card_name = make_image_name($config[:tarot], 1)
card_image = pdf.image(card_name)
ratio = card_image.width.to_f / card_image.height.to_f

puts "Card image width: #{card_image.width}px, Card image height: #{card_image.height}px, Ratio: #{ratio}" if $config[:verbose]

# compute rows & columns

number_specified = [:rows, :cols, :width, :height].inject(0) {|count, sym| count + ($config[sym].nil? ? 0 : 1)}

if $config[:verbose]
  puts "Card grid specifications:"
  [:rows, :cols, :width, :height].each {|sym| puts "  #{sym.to_s}: #{$config[sym].nil? ? 'nil' : $config[sym]}" }
end

if number_specified == 0
  puts 'Must specify one of rows/cols/width/height'
  exit
elsif number_specified > 1
  puts 'Must specify only one of rows/cols/width/height'
  exit
end

# process card width or height to get columns or rows

if !$config[:width].nil?
  matches = $config[:width].downcase.match(/(\d+)(in|mm)?/)
  if matches.nil?
    puts "Bad card width: #{$config[:width]}"
    exit
  else
    width = matches[1].to_i
    width_unit = matches[2]
    card_width_pt = width_unit == 'in' ? in2pt(width) : mm2pt(width)
    puts "Card width: #{card_width_pt}" if $config[:verbose]
    $config[:cols] = (page_width_pt / card_width_pt).floor
    puts "Computed columns: #{$config[:cols]}"
  end
elsif !$config[:height].nil?
  matches = $config[:height].downcase.match(/(\d+)(in|mm)?/)
  if matches.nil?
    puts "Bad card height: #{$config[:height]}"
    exit
  else
    height = matches[1].to_i
    height_unit = matches[2]
    card_height_pt = height_unit == 'in' ? in2pt(height) : mm2pt(height)
    $config[:rows] = (page_height_pt / card_height_pt).floor
  end
end

# based on known columns or rows, compute the other

if $config[:rows].nil?
  $config[:rows] = ($config[:cols] * ratio).ceil
elsif $config[:cols].nil?
  $config[:cols] = ($config[:rows] / ratio).floor
end

puts "rows: #{$config[:rows]}, cols: #{$config[:cols]}"
puts "#{$config[:dups]} copies of each card"


cards_per_page = $config[:rows] * $config[:cols]

puts "Cards per page: #{cards_per_page}"


card_width = (page_width_pt / $config[:cols]).floor
card_height = (card_width / ratio).floor

cards = ((1..78).collect {|card_number| [card_number] * $config[:dups]}).flatten

pdf.delete_page(0)              # clean out spurious pages
pdf.delete_page(0)
pdf.delete_page(0)

pdf.start_new_page              # start a fresh page

card_on_page = -1

cards.each_with_index do |card_number, card_index|

  card = make_image_name($config[:tarot], card_number)

  card_on_page = card_index % cards_per_page
  r = card_on_page / $config[:cols]
  c = card_on_page % $config[:cols]

  pdf.image(card, at: [card_width * c, card_height * (r + 1)], width: card_width, height: card_height)

  if card_on_page == cards_per_page - 1 # is the page full?
    pdf.start_new_page
    card_on_page = -1
  end
end

if card_on_page == -1           # if all pages are full, there'll be an empty one at the end
  pdf.delete_page(-1)
end

# write the output file
output_file = File.join($config[:dir], $config[:file].nil? ? "#{$config[:tarot]}-#{$config[:rows]}x#{$config[:cols]}-#{$config[:dups]}.pdf" : $config[:file])
puts "Writing to #{output_file}" if $config[:verbose]

pdf.render_file(output_file)
