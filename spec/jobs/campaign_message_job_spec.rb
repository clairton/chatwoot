require 'rails_helper'

RSpec.describe CampaignMessageJob do
  subject(:job) do
    described_class.perform_later(
      campaign.account_id,
      campaign.inbox_id,
      phone_number,
      campaign.message
    )
  end

  let(:account) { create(:account) }
  let!(:unoapi_channel) { create(:channel_whatsapp, provider: 'unoapi', sync_templates: false, validate_provider_config: false) }
  let!(:unoapi_inbox) { create(:inbox, channel: unoapi_channel) }
  let(:phone_number) { Faker::PhoneNumber.cell_phone_in_e164 }
  let!(:campaign) do
    create(:campaign, inbox: unoapi_inbox, account: account, audience: [phone_number])
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(
        campaign.account_id,
        campaign.inbox_id,
        phone_number,
        campaign.message
      )
      .on_queue('high')
  end

  context 'when the job is triggered on a new message' do
    let(:process_service) { double }

    before do
      allow(process_service).to receive(:perform)
    end

    it 'calls create a message' do
      count = Message.count
      described_class.perform_now(
        campaign.account_id,
        campaign.inbox_id,
        phone_number,
        campaign.message
      )
      expect(Message.count).to be count + 1
    end
  end
end
