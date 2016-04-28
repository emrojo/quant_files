#!/Users/emr/.rvm/rubies/ruby-1.9.3-p551/bin/ruby

require 'csv'
require 'fileutils'

require 'net/http'

SS_URL = "http://localhost:3000/api/1/"
SS_KEY = "development"


ARCHIVE_FOLDER = 'archive/'
INBOX_FOLDER = 'example_files/'

class MoveFile
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

  def get_barcode
    csv_plate_barcode_line[1] if valid_content?
  end

end

def get_files_from_folder(folder)
  Dir.entries(folder)
end

class ApiConnection
  attr_reader :host, :port

  def initialize(host, port)
    @host = host
    @port = port
  end

  def headers

  end

  def request_from_path(path, headers)
    Net::HTTP.new(@host, @port).get2(path, headers)
  end

  def ss_api
    self.api ||= Sequencescape::Api.new(:url => SS_URL, :authorisation => SS_KEY)
  end

end

def request_uuid(barcode)
  response = ApiConnection.new("localhost", "4567").request_from_path("/assays/#{barcode}/input", { "Content-Type" => "text/uuid" })
  uuid = response.body unless response.is_a?(Net::HTTPNotFound)
end


def upload_qc_file_to_ss_with_api(uuid, filename)
  ss_api.find(uuid).qc_files.create_from_file(filename, filename)
end

def perform_for_file(url, file, filename, headers)
  uri = URI.parse(url)
  file_content = file.read
  puts "file reading: #{file_content}"
  Net::HTTP.start(uri.host, uri.port) do |connection|
    #connection.read_timeout = "3000"
    file_headers = headers.merge!({'Content-Disposition'=> "form-data; filename=\"#{filename}\""})
    request = Net::HTTP.const_get("Post").new(uri.request_uri, file_headers)
    request.content_type = 'sequencescape/qc_file'
    #request.body         = body.to_json
    request.body         = file_content
    connection.request(request)
    #yield(connection.request(request))
  end
end

def upload_qc_file_to_ss_with_http(uuid, current_movefile)
  perform_for_file(SS_URL+uuid+"/qc_files", File.open(current_movefile.absolute_filename, "r"), current_movefile.filename,  {
    "X-Sequencescape-Client-ID" => SS_KEY,
    "Sequencescape-Client-ID" => SS_KEY
    })
end

def process_file(filename)
  current_movefile = MoveFile.new(filename)
  current_movefile.lock

  uuid = request_uuid(current_movefile.get_barcode)

  if uuid
    upload_qc_file_to_ss_with_http(uuid, current_movefile)
    #current_movefile.archive
  else
    #current_movefile.archive(".unknown_uuid")
  end
ensure
  current_movefile.unlock
end


get_files_from_folder(INBOX_FOLDER).each do |filename|
  process_file(filename) if filename.match(/\.csv$/i)
end
