require 'fedex/request/base'

module Fedex
  module Request
    class Shipment < Base
      attr_reader :response_details

      def initialize(credentials, options={})
        super
        requires!(options, :service_type)
        # Label specification is required even if we're not using it.
        @label_specification = {
          :label_format_type => 'COMMON2D',
          :image_type => 'PDF',
          :label_stock_type => 'PAPER_8.5X11_TOP_HALF_LABEL'
        }
        @label_specification.merge! options[:label_specification] if options[:label_specification]
        @customer_specified_detail = options[:customer_specified_detail] if options[:customer_specified_detail]
      end

      # Sends post request to Fedex web service and parse the response.
      # A label file is created with the label at the specified location.
      # The parsed Fedex response is available in #response_details
      # e.g. response_details[:completed_shipment_detail][:completed_package_details][:tracking_ids][:tracking_number]
      def process_request
        api_response = self.class.post api_url, :body => build_xml
        puts api_response if @debug
        response = parse_response(api_response)
        if success?(response)
          success_response(api_response, response)
        else
          failure_response(api_response, response)
        end
      end

      private

      # Add information for shipments
      def add_requested_shipment(xml)
        xml.RequestedShipment{
          xml.ShipTimestamp @shipping_options[:ship_timestamp] ||= Time.now.utc.iso8601(2)
          xml.DropoffType @shipping_options[:drop_off_type] ||= "REGULAR_PICKUP"
          xml.ServiceType service_type
          xml.PackagingType @shipping_options[:packaging_type] ||= "YOUR_PACKAGING"
          add_total_weight(xml) if @mps.has_key? :total_weight
          add_shipper(xml)
          add_recipient(xml)
          add_shipping_charges_payment(xml)
          add_special_services(xml) if @shipping_options[:return_reason] || @shipping_options[:cod] || @shipping_options[:saturday_delivery]
          add_customs_clearance(xml) if @customs_clearance_detail
          add_custom_components(xml)
          xml.RateRequestTypes "ACCOUNT"
          add_packages(xml)
        }
      end

      def add_total_weight(xml)
        if @mps.has_key? :total_weight
          xml.TotalWeight{
            xml.Units @mps[:total_weight][:units]
            xml.Value @mps[:total_weight][:value]
          }
        end
      end

      # Hook that can be used to add custom parts.
      def add_custom_components(xml)
        add_label_specification xml
      end

      # Add the label specification
      def add_label_specification(xml)
        xml.LabelSpecification {
          xml.LabelFormatType @label_specification[:label_format_type]
          xml.ImageType @label_specification[:image_type]
          xml.LabelStockType @label_specification[:label_stock_type]
          xml.CustomerSpecifiedDetail{ hash_to_xml(xml, @customer_specified_detail) } if @customer_specified_detail
        }
      end

      def add_special_services(xml)
        xml.SpecialServicesRequested {
          if @shipping_options[:return_reason]
            xml.SpecialServiceTypes "RETURN_SHIPMENT"
            xml.ReturnShipmentDetail {
              xml.ReturnType "PRINT_RETURN_LABEL"
              xml.Rma {
                xml.Reason "#{@shipping_options[:return_reason]}"
              }
            }
          end
          if @shipping_options[:cod]
            xml.SpecialServiceTypes "COD"
            xml.CodDetail {
              xml.CodCollectionAmount {
                xml.Currency @shipping_options[:cod][:currency].upcase if @shipping_options[:cod][:currency]
                xml.Amount @shipping_options[:cod][:amount] if @shipping_options[:cod][:amount]
              }
              xml.CollectionType @shipping_options[:cod][:collection_type] if @shipping_options[:cod][:collection_type]
            }
          end
          if @shipping_options[:saturday_delivery]
            xml.SpecialServiceTypes "SATURDAY_DELIVERY"
          end
        }
      end

      # Callback used after a failed shipment response.
      def failure_response(api_response, response)
        puts "#############################################################################"
        puts "#{api_response.inspect}"
        puts "#############################################################################"
        puts "#{response.inspect}"
        puts "#############################################################################"
        puts "#{response[:envelope][:body][:process_shipment_reply].inspect}"
        puts "#############################################################################"

        error_message = if response[:process_shipment_reply]
          [response[:process_shipment_reply][:notifications]].flatten.first[:message]
        else
          "#{api_response["Fault"]["detail"]["fault"]["reason"]}\n--#{api_response["Fault"]["detail"]["fault"]["details"]["ValidationFailureDetail"]["message"].join("\n--")}"
        end rescue $1
        raise RateError, error_message
      end

      # Callback used after a successful shipment response.
      def success_response(api_response, response)
        @response_details = response[:process_shipment_reply]
      end

      # Build xml Fedex Web Service request
      def build_xml
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.ProcessShipmentRequest(:xmlns => "http://fedex.com/ws/ship/v#{service[:version]}"){
            add_web_authentication_detail(xml)
            add_client_detail(xml)
            add_version(xml)
            add_requested_shipment(xml)
          }
        end
        puts "#############################################################################"
        puts "#{builder.doc.root.to_xml}"
        puts "#############################################################################"
        #builder.doc.root.to_xml
        "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:v13=\"http://fedex.com/ws/ship/v13\">
   		<soapenv:Header/>
   		<soapenv:Body>
        		<v13:ProcessShipmentRequest>
         			<v13:WebAuthenticationDetail>
            				<v13:UserCredential>
               					<v13:Key>r50uWmpOG8Nc25pG</v13:Key>
               					<v13:Password>CZq58EtnUWQKfxeGKMF2PsRND</v13:Password>
            				</v13:UserCredential>
         			</v13:WebAuthenticationDetail>
         			<v13:ClientDetail>
            				<v13:AccountNumber>510087348</v13:AccountNumber>
            				<v13:MeterNumber>118690984</v13:MeterNumber>
         			</v13:ClientDetail>
         			<v13:Version>
            				<v13:ServiceId>ship</v13:ServiceId>
            				<v13:Major>13</v13:Major>
            				<v13:Intermediate>0</v13:Intermediate>
            				<v13:Minor>0</v13:Minor>
         			</v13:Version>
         			<v13:RequestedShipment>
            				<v13:ShipTimestamp>2015-10-24T15:43:20</v13:ShipTimestamp>
            				<v13:DropoffType>REGULAR_PICKUP</v13:DropoffType>
            				<v13:ServiceType>STANDARD_OVERNIGHT</v13:ServiceType>
            				<v13:PackagingType>YOUR_PACKAGING</v13:PackagingType>
            				<v13:TotalWeight>
               					<v13:Units>KG</v13:Units>
               					<v13:Value>1</v13:Value>
            				</v13:TotalWeight>
            				<v13:Shipper>
               					<v13:AccountNumber>510087348</v13:AccountNumber>
               					<v13:Tins>
                  					<v13:TinType>BUSINESS_NATIONAL</v13:TinType>
                  					<v13:Number>SHPR1111</v13:Number>
                  					<v13:Usage>ANY</v13:Usage>
               					</v13:Tins>
               					<v13:Contact>
                  					<v13:PersonName>himanshu</v13:PersonName>
                  					<v13:CompanyName>s1 tech</v13:CompanyName>
                  					<v13:PhoneNumber>9876123432</v13:PhoneNumber>
               					</v13:Contact>
               					<v13:Address>
                  					<v13:StreetLines>217A, Oshiwara Ind. Center</v13:StreetLines>
                  					<v13:StreetLines>Oshiwara Bus Depot, Goregaon west</v13:StreetLines>
                  					<v13:City>Mumbai</v13:City>
                  					<v13:StateOrProvinceCode>MH</v13:StateOrProvinceCode>
                  					<v13:PostalCode>400104</v13:PostalCode>
                  					<v13:CountryCode>IN</v13:CountryCode>
                  					<v13:CountryName>INDIA</v13:CountryName>
               					</v13:Address>
            				</v13:Shipper>
            				<v13:Recipient>
               					<v13:Tins>
                  					<v13:TinType>BUSINESS_NATIONAL</v13:TinType>
                  					<v13:Number>RECPT1111</v13:Number>
                  					<v13:Usage>ANY</v13:Usage>
               					</v13:Tins>
               					<v13:Contact>
                  					<v13:PersonName>daivik garg</v13:PersonName>
                  					<v13:CompanyName>d1 tech</v13:CompanyName>
                  					<v13:PhoneNumber>989254464</v13:PhoneNumber>
               					</v13:Contact>
               					<v13:Address>
                  					<v13:StreetLines>C-1 FLAT NO-202 HYDE PARK RESIDENCY</v13:StreetLines>
                  					<v13:StreetLines>THANE WEST NEAR WONDER MALL THANE</v13:StreetLines>
                  					<v13:City>Mumbai</v13:City>
                  					<v13:StateOrProvinceCode>MH</v13:StateOrProvinceCode>
                  					<v13:PostalCode>400610</v13:PostalCode>
                  					<v13:CountryCode>IN</v13:CountryCode>
                  					<v13:CountryName>INDIA</v13:CountryName>
               					</v13:Address>
            				</v13:Recipient>
            				<v13:ShippingChargesPayment>
               					<v13:PaymentType>SENDER</v13:PaymentType>
               					<v13:Payor>
                  					<v13:ResponsibleParty>
                     						<v13:AccountNumber>510087348</v13:AccountNumber>
                     						<v13:Contact>
                  							<v13:PersonName>himanshu</v13:PersonName>
                  							<v13:CompanyName>s1 tech</v13:CompanyName>
                  							<v13:PhoneNumber>9876123432</v13:PhoneNumber>
                     						</v13:Contact>
                  					</v13:ResponsibleParty>
               					</v13:Payor>
            				</v13:ShippingChargesPayment>
                        		<v13:CustomsClearanceDetail>
               					<v13:DutiesPayment>
                  					<v13:PaymentType>SENDER</v13:PaymentType>
                  					<v13:Payor>
                     						<v13:ResponsibleParty>
									<v13:AccountNumber>510087348</v13:AccountNumber>
                        						<v13:Contact>
	                  							<v13:PersonName>himanshu</v13:PersonName>
        	          							<v13:CompanyName>s1 tech</v13:CompanyName>
                	  							<v13:PhoneNumber>9876123432</v13:PhoneNumber>
                        						</v13:Contact>
                     						</v13:ResponsibleParty>
                  					</v13:Payor>
               					</v13:DutiesPayment>
               					<v13:DocumentContent>NON_DOCUMENTS</v13:DocumentContent>
               					<v13:CustomsValue>
                  					<v13:Currency>INR</v13:Currency>
                  					<v13:Amount>2498.00</v13:Amount>
               					</v13:CustomsValue>
               					<v13:CommercialInvoice>
                  					<v13:Purpose>SOLD</v13:Purpose>
               					</v13:CommercialInvoice>
               					<v13:Commodities>
                  					<v13:Name>MOBILE PHONE</v13:Name>
                  					<v13:NumberOfPieces>1</v13:NumberOfPieces>
                  					<v13:Description>samsung s5 mobile</v13:Description>
                  					<v13:CountryOfManufacture>IN</v13:CountryOfManufacture>
                  					<v13:Weight>
                     						<v13:Units>KG</v13:Units>
                     						<v13:Value>1</v13:Value>
                  					</v13:Weight>
                  					<v13:Quantity>1</v13:Quantity>
                  					<v13:QuantityUnits>pc</v13:QuantityUnits>
                  				<v13:UnitPrice>
                     					<v13:Currency>INR</v13:Currency>
                     					<v13:Amount>2498.0</v13:Amount>
                  				</v13:UnitPrice>
                  				<v13:CustomsValue>
                     					<v13:Currency>INR</v13:Currency>
                     					<v13:Amount>2498.00</v13:Amount>
                  				</v13:CustomsValue>
               				</v13:Commodities>
            			</v13:CustomsClearanceDetail>
            			<v13:LabelSpecification>
               				<v13:LabelFormatType>COMMON2D</v13:LabelFormatType>
               				<v13:ImageType>PDF</v13:ImageType>
               				<v13:LabelStockType>PAPER_8.5X11_TOP_HALF_LABEL</v13:LabelStockType>
            			</v13:LabelSpecification>
            			<v13:RateRequestTypes>ACCOUNT</v13:RateRequestTypes>
            			<v13:PackageCount>1</v13:PackageCount>
            		<v13:RequestedPackageLineItems>
               			<v13:SequenceNumber>1</v13:SequenceNumber>
               			<v13:GroupNumber>1</v13:GroupNumber>
               			<v13:GroupPackageCount>1</v13:GroupPackageCount>
               			<v13:Weight>
                  			<v13:Units>KG</v13:Units>
                  			<v13:Value>1</v13:Value>
               			</v13:Weight>
               			<v13:Dimensions>
                  			<v13:Length>10</v13:Length>
                  			<v13:Width>12</v13:Width>
                  			<v13:Height>14</v13:Height>
                  			<v13:Units>CM</v13:Units>
               			</v13:Dimensions>
               			<v13:CustomerReferences>
                  			<v13:CustomerReferenceType>CUSTOMER_REFERENCE</v13:CustomerReferenceType>
                  			<v13:Value>6666</v13:Value>
               			</v13:CustomerReferences>
               			<v13:CustomerReferences>
                  			<v13:CustomerReferenceType>DEPARTMENT_NUMBER</v13:CustomerReferenceType>
                  			<v13:Value>7777</v13:Value>
               			</v13:CustomerReferences>
               			<v13:CustomerReferences>
                  			<v13:CustomerReferenceType>INVOICE_NUMBER</v13:CustomerReferenceType>
                  			<v13:Value>8888</v13:Value>
               			</v13:CustomerReferences>
            		</v13:RequestedPackageLineItems>
         	</v13:RequestedShipment>
      	</v13:ProcessShipmentRequest>   
      	</soapenv:Body>
	</soapenv:Envelope>"
      end

      def service
        { :id => 'ship', :version => Fedex::API_VERSION }
      end

      # Successful request
      def success?(response)
        response[:process_shipment_reply] &&
          %w{SUCCESS WARNING NOTE}.include?(response[:process_shipment_reply][:highest_severity])
      end

    end
  end
end
