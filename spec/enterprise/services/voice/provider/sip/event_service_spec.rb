require 'rails_helper'

describe Voice::Provider::Sip::EventService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_sip, account: account) }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:ringing_params) { { event: 'ringing', call_id: 'pbx-call-1', from: '+5511988887777', name: 'Maria' } }

  before do
    account.enable_features!('channel_voice')
    create(:inbox_member, user: agent, inbox: inbox, sip_uri: 'sip:1001@pbx.example.com')
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe 'ringing' do
    it 'creates the inbound call, its conversation and the voice_call message' do
      result = nil
      expect { result = described_class.new(inbox: inbox, params: ringing_params).perform }
        .to change(Call, :count).by(1).and change(inbox.conversations, :count).by(1)

      call = Call.sip.find_by(provider_call_id: 'pbx-call-1')
      expect(call).to have_attributes(direction: 'incoming', status: 'ringing', inbox_id: inbox.id)
      expect(call.contact).to have_attributes(name: 'Maria', phone_number: '+5511988887777')
      expect(call.message).to have_attributes(content_type: 'voice_call', message_type: 'incoming')
      expect(result).to include(action: 'ring', call_id: 'pbx-call-1', conversation_id: call.conversation.display_id)
    end

    it 'is idempotent for a repeated ringing event' do
      described_class.new(inbox: inbox, params: ringing_params).perform

      expect { described_class.new(inbox: inbox, params: ringing_params).perform }.not_to change(Call, :count)
    end

    it 'keeps a withheld caller id as the contact name without a phone number' do
      described_class.new(inbox: inbox, params: { event: 'ringing', call_id: 'pbx-call-1', from: 'anonymous' }).perform

      expect(Call.sip.last.contact).to have_attributes(name: 'anonymous', phone_number: nil)
    end

    it 'accepts a caller id sent as a number' do
      described_class.new(inbox: inbox, params: { event: 'ringing', call_id: 'pbx-call-1', from: 1001 }).perform

      expect(Call.sip.last.contact).to have_attributes(name: '1001', phone_number: nil)
    end

    it 'tells the PBX to reject the call when inbound calls are disabled' do
      channel.update!(provider_config: { 'inbound_calls_enabled' => false })

      result = nil
      expect { result = described_class.new(inbox: inbox, params: ringing_params).perform }.not_to change(Call, :count)

      expect(result).to eq(action: 'reject')
    end

    it 'rings the online members that have an extension' do
      create(:inbox_member, user: other_agent, inbox: inbox, sip_uri: 'sip:1002@pbx.example.com')
      OnlineStatusTracker.update_presence(account.id, 'User', agent.id)
      OnlineStatusTracker.set_status(account.id, agent.id, 'online')

      result = described_class.new(inbox: inbox, params: ringing_params).perform

      expect(result[:extensions]).to eq(['1001'])
    end

    it 'rings every member with an extension when nobody is online' do
      create(:inbox_member, user: other_agent, inbox: inbox, sip_uri: 'sip:1002@pbx.example.com')
      create(:inbox_member, inbox: inbox)

      result = described_class.new(inbox: inbox, params: ringing_params).perform

      expect(result[:extensions]).to contain_exactly('1001', '1002')
    end

    it 'rings only the assignee when the conversation already has one' do
      create(:inbox_member, user: other_agent, inbox: inbox, sip_uri: 'sip:1002@pbx.example.com')
      contact = create(:contact, account: account, phone_number: '+5511988887777')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '+5511988887777')
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, assignee: other_agent)

      result = described_class.new(inbox: inbox, params: ringing_params).perform

      expect(result[:extensions]).to eq(['1002'])
    end
  end

  describe 'answered' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:call) do
      create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                    provider: :sip, direction: :incoming, status: 'ringing', provider_call_id: 'pbx-call-1')
    end

    it 'marks the call in progress and credits the agent who owns the extension' do
      result = described_class.new(inbox: inbox, params: { event: 'answered', call_id: 'pbx-call-1', extension: '1001' }).perform

      expect(result).to eq(call_id: 'pbx-call-1', status: 'in-progress')
      expect(call.reload).to have_attributes(status: 'in_progress', accepted_by_agent_id: agent.id, started_at: be_present)
      expect(conversation.reload.assignee_id).to eq(agent.id)
      expect(ActionCable.server).to have_received(:broadcast).with(
        "account_#{account.id}", hash_including(event: 'voice_call.accepted', data: hash_including(accepted_by_agent_id: agent.id))
      )
    end

    it 'hands a conversation assigned to someone else to the agent who answered' do
      create(:inbox_member, user: other_agent, inbox: inbox)
      conversation.update!(assignee: other_agent)

      described_class.new(inbox: inbox, params: { event: 'answered', call_id: 'pbx-call-1', extension: '1001' }).perform

      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'does not credit anyone when the extension is not sent' do
      create(:inbox_member, user: other_agent, inbox: inbox)

      described_class.new(inbox: inbox, params: { event: 'answered', call_id: 'pbx-call-1' }).perform

      expect(call.reload).to have_attributes(status: 'in_progress', accepted_by_agent_id: nil)
    end

    it 'keeps the first agent when a second answered event names another extension' do
      create(:inbox_member, user: other_agent, inbox: inbox, sip_uri: 'sip:1002@pbx.example.com')
      described_class.new(inbox: inbox, params: { event: 'answered', call_id: 'pbx-call-1', extension: '1001' }).perform

      described_class.new(inbox: inbox, params: { event: 'answered', call_id: 'pbx-call-1', extension: '1002' }).perform

      expect(call.reload.accepted_by_agent_id).to eq(agent.id)
    end

    it 'does not broadcast accepted for an outbound call' do
      call.update!(direction: :outgoing, accepted_by_agent_id: agent.id)

      described_class.new(inbox: inbox, params: { event: 'answered', call_id: 'pbx-call-1' }).perform

      expect(call.reload.status).to eq('in_progress')
      expect(ActionCable.server).not_to have_received(:broadcast).with(
        "account_#{account.id}", hash_including(event: 'voice_call.accepted')
      )
    end
  end

  describe 'terminal events' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:call) do
      create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                    provider: :sip, direction: :incoming, status: 'ringing', provider_call_id: 'pbx-call-1')
    end

    it 'completes an answered call with the reported duration' do
      call.update!(status: 'in_progress', started_at: 1.minute.ago)

      result = described_class.new(inbox: inbox, params: { event: 'completed', call_id: 'pbx-call-1', duration: '58' }).perform

      expect(result).to eq(call_id: 'pbx-call-1', status: 'completed')
      expect(call.reload).to have_attributes(status: 'completed', duration_seconds: 58, end_reason: 'completed')
      expect(ActionCable.server).to have_received(:broadcast).with(
        "account_#{account.id}", hash_including(event: 'voice_call.ended', data: hash_including(status: 'completed'))
      )
    end

    it 'records a caller hangup before pickup as a missed call' do
      described_class.new(inbox: inbox, params: { event: 'canceled', call_id: 'pbx-call-1' }).perform

      expect(call.reload).to have_attributes(status: 'no_answer', end_reason: 'canceled')
    end

    it 'does not overwrite a call the agent already ended' do
      call.update!(status: 'completed', end_reason: 'agent_hangup', duration_seconds: 12)

      described_class.new(inbox: inbox, params: { event: 'completed', call_id: 'pbx-call-1', duration: '15' }).perform

      expect(call.reload).to have_attributes(status: 'completed', end_reason: 'agent_hangup', duration_seconds: 12)
      expect(ActionCable.server).not_to have_received(:broadcast).with(
        "account_#{account.id}", hash_including(event: 'voice_call.ended')
      )
    end

    it 'raises when the call is unknown' do
      expect { described_class.new(inbox: inbox, params: { event: 'completed', call_id: 'missing' }).perform }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
