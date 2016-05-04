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
ERRORS_FOLDER = 'errors/'

class FileMove

  attr_reader :filename, :lock_file, :barcode_line, :processing_csv

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

  def unlocked?
    !locked?
  end

  def csv_plate_barcode_line
    @processing_csv = true
    @barcode_line ||= CSV.read(absolute_filename).find {|line| line[0] == 'Assay Plate Barcode'}
    @processing_csv = false
    barcode_line
  rescue ArgumentError
    $stdout.puts "Argument error in csv file #{filename}"
    barcode_line = nil
  end

  public
  def absolute_filename
    @path + filename
  end

  def lock
    @lock_file = File.open(@path + lock_filename, File::WRONLY|File::CREAT)
    @lock_file.flock(File::LOCK_EX|File::LOCK_NB)
  end

  def unlock
    if lock_file
      @lock_file.flock(File::LOCK_UN)
      File.unlink(@path + lock_filename)
    end
  end

  def move_to_errors
    FileUtils.mv(@path + filename, ERRORS_FOLDER + filename)
  end

  def archive
    FileUtils.mv(@path + filename, ARCHIVE_FOLDER + filename)
  end

  def valid_content?
    csv_plate_barcode_line
  end

  def barcode
    return unless valid_content?
    csv_plate_barcode_line[1].strip
  end

  def safe_shutdown
    if processing_csv
      $stdout.puts "Something went wrong while processing csv file #{filename}"
      move_to_errors
    end
  ensure
    unlock
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
    return unless movefile.barcode
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
  if current_filemove.unlocked? && current_filemove.lock
    return $stdout.puts "Barcode section was not found in the file #{current_filemove.absolute_filename}" unless current_filemove.barcode
    quant_process = QuantFileProcess.new(current_filemove)
    quant_process.request_uuid
    if quant_process.uuid
      quant_process.upload_qc_file_to_ss_with_http
      if quant_process.code == 500
        current_filemove.move_to_errors
        $stderr.puts "HTTP 500 server side problem"
      elsif quant_process.code !=503
        current_filemove.archive
      end
    else
      $stdout.puts "The barcode #{current_filemove.barcode} was not found in quant"
    end
  end
ensure
  current_filemove.safe_shutdown
end


Dir.entries(INBOX_FOLDER).each do |filename|
  process_file(filename) if filename.match(/\.csv$/i)
end
