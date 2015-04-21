require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/installed_app'


module FileSecrets


  def authorize_flow(scope)
    # Initialize Google+ API. Note this will make a request to the
    # discovery service every time, so be sure to use serialization
    # in your production code. Check the samples for more details.
    #plus = client.discovered_api('plus')

    # Load client secrets from your client_secrets.json.
    client_secrets = Google::APIClient::ClientSecrets.load

    # Run installed application flow. Check the samples for a more
    # complete example that saves the credentials between runs.
    flow = Google::APIClient::InstalledAppFlow.new(
      :client_id => client_secrets.client_id,
      :client_secret => client_secrets.client_secret,
      :scope => Array(scope)
    )
    flow.authorize
  end

end

module Google

  # Initialize the client.
  def self.client
    @client ||= Google::APIClient.new(
      :application_name => 'Example Ruby application',
      :application_version => '1.0.0'
    )
  end

end


module Google



  class Contacts

    include FileSecrets

    attr_reader :client

    SCOPE = 'https://www.google.com/m8/feeds'

    attr_reader  :client

    def initialize(client)
      @client = client
      @client.authorization = authorize_flow(SCOPE)
    end

    def execute(options = {})
      client.execute({ headers: { 'GData-Version' => '3.0', 'Content-Type' => 'application/json' } }.merge(options))
    end

    def fetch_all(options = {})
      execute(uri: "https://www.google.com/m8/feeds/contacts/default/full",
              parameters: { 'alt' => 'json',
                            'updated-min' => options[:since] || '2011-03-16T00:00:00',
                            'max-results' => '100000' }).data
    end

    def contacts_feed
      @contacts_feed ||= fetch_all
    end

    def entry_enum(feed)
      fib = Fiber.new do
        feed['feed']['entry'].each do |entry|
          Fiber.yield entry
        end
      end
      fib
    end

    def contacts2
      fetch_all['feed']['entry'].map do |contact|
        {
          emails: extract_schema(contact['gd$email']),
          phone_numbers: extract_schema(contact['gd$phoneNumber']),
          handles: extract_schema(contact['gd$im']),
          addresses: extract_schema(contact['gd$structuredPostalAddress']),
          name_data: cleanse_gdata(contact['gd$name']),
          nickname: contact['gContact$nickname'] && contact['gContact$nickname']['$t'],
          websites: extract_schema(contact['gContact$website']),
          organizations: extract_schema(contact['gd$organization']),
          events: extract_schema(contact['gContact$event']),
          birthday: contact['gContact$birthday'].try(:[], "when")
        }.tap do |basic_data|
          # Extract a few useful bits from the basic data
          basic_data[:full_name] = basic_data[:name_data].try(:[], :full_name)
          primary_email_data = basic_data[:emails].find { |type, email| email[:primary] }
          if primary_email_data
            basic_data[:primary_email] = primary_email_data.last[:address]
          end
        end
      end
    end

    protected

    # Turn an array of hashes into a hash with keys based on the original hash's 'rel' values, flatten, and cleanse.
    def extract_schema(records)
      (records || []).inject({}) do |memo, record|
        key = (record['rel'] || 'unknown').split('#').last.to_sym
        value = cleanse_gdata(record.except('rel'))
        value[:primary] = true if value[:primary] == 'true' # cast to a boolean for primary entries
        value[:protocol] = value[:protocol].split('#').last if value[:protocol] && value[:protocol].present? # clean namespace from handle protocols
        value = value[:$t] if value[:$t].present? # flatten out entries with keys of '$t'
        value = value[:href] if value.is_a?(Hash) && value.keys == [:href] # flatten out entries with keys of 'href'
        memo[key] = value
        memo
      end
    end

    # Transform this
    #     {"gd$fullName"=>{"$t"=>"Bob Smith"},
    #      "gd$givenName"=>{"$t"=>"Bob"},
    #      "gd$familyName"=>{"$t"=>"Smith"}}
    # into this
    #     { :full_name => "Bob Smith",
    #       :given_name => "Bob",
    #       :family_name => "Smith" }
    def cleanse_gdata(hash)
      (hash || {}).inject({}) do |m, (k, v)|
        k = k.gsub(/\Agd\$/, '').underscore # remove leading 'gd$' on key names and switch to underscores
        v = v['$t'] if v.is_a?(Hash) && v.keys == ['$t'] # flatten out { '$t' => "value" } results
        m[k.to_sym] = v
        m
      end
    end
  end
end

if $0 == __FILE__
   require 'pry'
  client = Google.client
  wrap = Google::Contacts.new(client)
  binding.pry
  feed = wrap.contacts_feed
  entries = entry_enum(feed)



  binding.pry

  wrap.contacts_feed

end
