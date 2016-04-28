#!/Users/emr/.rvm/rubies/ruby-1.9.3-p551/bin/ruby

require 'csv'
require 'fileutils'

require 'net/http'


ARCHIVE_FOLDER = 'archive/'
INBOX_FOLDER = 'example_files/'

class MoveFile
  attr_reader :filename


  def initialize(filename)
    @filename = filename
    @path = INBOX_FOLDER
  end

  private

  def filename
    @filename
  end

  def lock_filename
    @filename + ".lock"
  end

  def locked?
    File.exists?(@path + lock_filename)
  end

  def csv_plate_barcode_line
    CSV.read(absolute_filename).find {|line| line[0] == 'Assay Plate Barcode'}
  end

  public
  def absolute_filename
    @path + (locked? ?  lock_filename : filename)
  end

  def lock
    File.rename(@path + filename, @path + lock_filename)
  end

  def unlock
    File.rename(@path + lock_filename, @path + filename) if locked?
  end

  def archive
    FileUtils.mv(@path + lock_filename, ARCHIVE_FOLDER + filename)
    @path = ARCHIVE_FOLDER
  end

  def valid_content?
    csv_plate_barcode_line
  end

  def get_barcode
    csv_plate_barcode_line[1] if valid_content?
  end

end

def get_files_from_folder(folder)
  Dir.entries(folder)
end

def headers
  {
    "Content-Type" => "text/uuid"
  }
end

def request_uuid(barcode)
  httpcall = Net::HTTP.new("localhost", "4567")
  response = httpcall.get2("/assays/#{barcode}/input", headers)
  uuid = response.body unless response.is_a?(Net::HTTPNotFound)
end

def upload_qc_file_to_ss(uuid, filename)
end


def process_file(filename)
  current_movefile = MoveFile.new(filename)
  current_movefile.lock

  uuid = request_uuid(current_movefile.get_barcode)

  puts uuid

  upload_qc_file_to_ss(uuid, filename)


  #current_movefile.archive
ensure
  current_movefile.unlock
end


get_files_from_folder(INBOX_FOLDER).each do |filename|
  process_file(filename) if filename.match(/\.csv$/i)
end
