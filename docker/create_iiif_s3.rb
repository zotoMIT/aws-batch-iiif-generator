#!/usr/bin/env ruby

# A generator for IIIF compatible image tiles and metadata
# Try "./create_iiif_s3.rb -h"
#
require 'iiif_s3'
require 'open-uri'
require 'optparse'
require_relative '../../lib/iiif_s3/manifest_override'
IiifS3::Manifest.prepend IiifS3::ManifestOverride
require_relative 'lib/iiif_s3/image_tile_override'
IiifS3::ImageTile.prepend IiifS3::ImageTileOverride

# Create directories on local disk for manifests/tiles to upload them to S3
def create_directories(path)
  FileUtils.mkdir_p(path) unless Dir.exists?(path)
end

# Get label and description metadata from csv file
def get_metadata(csv_url, id)
  begin
    open(csv_url) do |u|
      csv_file_name = File.basename(csv_url)
      csv_file_path = "#{@config.output_dir}/#{csv_file_name}"
      File.open(csv_file_path, 'wb') { |f| f.write(u.read) }
      CSV.read(csv_file_path, 'r:bom|utf-8', headers: true).each do |row|
        if row.header?("Identifier")
          if row.field("Identifier") == id
            return row.field("Title"), row.field("Description")
          end
        else
          puts "No Identifier header found"
          return
        end
      end
      puts "No matching Identifier found"
    end
  rescue StandardError => e
    puts "An error occurred processing #{csv_url}: #{e.message}"
  end
end

def add_image(file, id, idx)
  name = File.basename(file, File.extname(file))
  page_num = idx + 1
  label, description = get_metadata(@csv_url, id)
  obj = {
    "path" => "#{file}",
    "id"       => id,
    "label"    => label,
    "is_master" => page_num == 1,
    "page_number" => page_num,
    "is_document" => false,
    "description" => description,
  }

  obj["section"] = "p#{page_num}"
  obj["section_label"] = "Page #{page_num}"
  @data.push IiifS3::ImageRecord.new(obj)
end

options = {}
optparse = OptionParser.new do |parser|
  parser.banner = "Usage: create_iiif_s3.rb -m csv_metadata_file -i image_folder_path -b manifest_base_path -r manifest_root_folder -[no-]u"

  # short option, long option, description of the option
  parser.on("-m", "--manifest_file File", "Manifest CSV file") do |manifest_file|
    options[:manifest_file] = manifest_file
  end
  parser.on("-i", "--image_folder Path", "Path to image folder") do |img_folder|
    options[:image_folder] = img_folder
  end
  parser.on("-b", "--base_path Path", "Base path of manifest file") do |base_path|
    options[:base_url] = base_path
  end
  parser.on("-r", "--root_folder Path", "Path to root folder") do |root_folder|
    options[:root_folder] = root_folder
  end
  options[:upload_to_s3] = false
  parser.on('-u', '--[no-]upload_to_s3', 'Upload manifest/tiles to s3') do
    options[:upload_to_s3] = true
  end
  parser.on_tail("-h", "--help", "Prints this help") do
    puts parser
    exit
  end
end.parse!

unless @csv_url = options[:manifest_file]
  puts "Require manifest_file!"
  puts "Try './create_iiif_s3.rb -h'"
  exit
else
  begin
    csv_name = File.basename(@csv_url)
    # look for collection id with pattern, e.g., Ms1990_025
    collection_id = csv_name.scan(/Ms\d{4}_\d{3}/)[0]
    unless image_folder_path = options[:image_folder]
      puts "Require path to image folder!"
      puts "Try './create_iiif_s3.rb -h'"
      exit
    else
      begin
        # path to the image files end with "obj_id/image.tif"
        @input_folder = image_folder_path.slice(image_folder_path.index("#{collection_id}")..-1)
        # sort image files in the image folder
        @image_files = Dir[image_folder_path + "*"].sort
      rescue StandardError => e
        puts "An error occurred processing image folder at #{image_folder_path}: #{e.message}"
      end
    end
  rescue StandardError => e
      puts "An error occurred process manifest file #{@csv_url}: #{e.message}"
  end
end

# Setup Temporary stores
@data = []
# Set up configuration variables
opts = {}
unless opts[:base_url] = options[:base_url]
  puts "Require base path to manifest file!"
  puts "Try './create_iiif_s3.rb -h'"
  exit
end
opts[:image_directory_name] = "tiles"
opts[:output_dir] = "tmp"
opts[:variants] = { "reference" => 600, "access" => 1200}
# get the option if upload to S3, absence is false, presence is true
opts[:upload_to_s3] = options[:upload_to_s3]
puts "upload to s3: #{opts[:upload_to_s3]}"
opts[:image_types] = [".jpg", ".tif", ".jpeg", ".tiff"]
opts[:document_file_types] = [".pdf"]
# prefix uses manifest_root_folder
unless options[:root_folder]
  puts "Require path to root folder"
  puts "Try './create_iiif_s3.rb -h'"
  exit
else
  opts[:prefix] = "#{options[:root_folder]}/#{@input_folder.split('/')[0..-3].join('/')}"
end

iiif = IiifS3::Builder.new(opts)
@config = iiif.config

path = "#{@config.output_dir}#{@config.prefix}/"
create_directories(path)

# generate a path on disk for "output_dir/prefix/image_dir"
img_dir = "#{path}#{@config.image_directory_name}/".split("/")[0...-1].join("/")
create_directories(img_dir)

id = @input_folder.split("/")[-2]

@image_files.each_with_index do |image_file, idx|
  add_image(image_file, id, idx)
end

iiif.load(@data)
iiif.process_data
