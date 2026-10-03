FactoryBot.define do
  factory :channel_sip, class: 'Channel::Sip' do
    url { 'wss://pbx.example.com:8089/ws' }
    sequence(:phone_number) { |n| "+5511999#{n.to_s.rjust(5, '0')}" }
    account
    after(:build) do |channel|
      channel.inbox ||= create(:inbox, account: channel.account)
    end
  end
end
