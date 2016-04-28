# myapp.rb
require 'sinatra'
require 'pry'
BARCODES = {
  "0000000000001" => "00000000-0000-0000-0000-000000000001"
}


get '/assays/:barcode/input' do
  return BARCODES[params['barcode']] if BARCODES.has_key?(params['barcode']) && (request.env['CONTENT_TYPE'] == 'text/uuid')
  status 404
end

