#!/Users/emr/.rvm/rubies/ruby-1.9.3-p551/bin/ruby

require 'csv'
require 'fileutils'
require 'net/http'


QUANT_SERVICE_HOST="localhost"
QUANT_SERVICE_PORT="4567"

SS_URL = "http://localhost:3000/api/1/"
SS_KEY = "development"

ARCHIVE_FOLDER = 'archive/'
INBOX_FOLDER = 'example_files/'

class FileMove

  attr_reader :filename

  def initialize(filename)
    @filename = filename
    @path = INBOX_FOLDER
  end

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

  def archive(tag="")
    FileUtils.mv(@path + lock_filename, ARCHIVE_FOLDER + filename + tag)
    @path = ARCHIVE_FOLDER
  end

  def valid_content?
    csv_plate_barcode_line
  end

  def barcode
    csv_plate_barcode_line[1].strip if valid_content?
  end
end


class QuantFileProcess

  attr_reader :uuid, :movefile, :code

  def initialize(movefile)
    @movefile = movefile
  end

  def request_from_path(host, port, path, headers)
    Net::HTTP.new(host, port).get2(path, headers)
  end

  def request_uuid
    quant_service_headers = { "Content-Type" => "text/uuid" }
    quant_service_url = "/assays/#{@movefile.barcode}/input"
    response = request_from_path(QUANT_SERVICE_HOST, QUANT_SERVICE_PORT, quant_service_url, quant_service_headers)
    @uuid = response.body unless response.is_a?(Net::HTTPNotFound)
  end

  def perform_for_file(url, file, filename, headers)
    uri = URI.parse(url)
    file_content = file.read
    Net::HTTP.start(uri.host, uri.port) do |connection|
      file_headers = headers.merge!({'Content-Disposition'=> "form-data; filename=\"#{filename}\""})
      request = Net::HTTP.const_get("Post").new(uri.request_uri, file_headers)
      request.content_type = 'sequencescape/qc_file'
      request.body         = file_content
      response = connection.request(request)
      @code = response.code
    end
  end

  def upload_qc_file_to_ss_with_http
    ss_service_headers = { "X-Sequencescape-Client-ID" => SS_KEY, "Sequencescape-Client-ID" => SS_KEY }
    perform_for_file(SS_URL+uuid+"/qc_files", File.open(@movefile.absolute_filename, "r"), @movefile.filename,  ss_service_headers)
  end

end

def process_file(filename)
  current_filemove = FileMove.new(filename)
  current_filemove.lock

  quant_process = QuantFileProcess.new(current_filemove)

  quant_process.request_uuid
  if quant_process.uuid
    quant_process.upload_qc_file_to_ss_with_http
    current_filemove.archive(".http_code_#{quant_process.code}")
  else
    current_filemove.archive(".unknown_uuid")
  end
ensure
  current_filemove.unlock
end


Dir.entries(INBOX_FOLDER).each do |filename|
  process_file(filename) if filename.match(/\.csv$/i)
end
