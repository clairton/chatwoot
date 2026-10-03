require 'rails_helper'

describe Voice::Provider::Sip::CallService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_sip, account: account) }
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                  provider: :sip, direction: :incoming, status: 'ringing', provider_call_id: 'pbx-call-1')
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe '#accept' do
    it 'transitions the call to in_progress without an SDP answer' do
      described_class.new(call: call, agent: agent).accept

      expect(call.reload).to have_attributes(status: 'in_progress', accepted_by_agent_id: agent.id, started_at: be_present)
      expect(ActionCable.server).to have_received(:broadcast).with(
        "account_#{account.id}", hash_including(event: 'voice_call.accepted', data: hash_including(provider: 'sip'))
      )
    end

    it 'claims the conversation when no assignee is set' do
      described_class.new(call: call, agent: agent).accept

      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'hands a conversation assigned to someone else to the agent who answered' do
      other_agent = create(:user, account: account)
      create(:inbox_member, user: other_agent, inbox: inbox)
      create(:inbox_member, user: agent, inbox: inbox)
      conversation.update!(assignee: other_agent)

      described_class.new(call: call, agent: agent).accept

      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'keeps the assignee of a conversation when the agent places an outbound call in it' do
      other_agent = create(:user, account: account)
      create(:inbox_member, user: other_agent, inbox: inbox)
      conversation.update!(assignee: other_agent)
      call.update!(direction: :outgoing, accepted_by_agent_id: agent.id)

      described_class.new(call: call, agent: agent).accept

      expect(conversation.reload.assignee_id).to eq(other_agent.id)
    end

    it 'keeps the AgentBot owner when accepting the call' do
      agent_bot = create(:agent_bot, account: account)
      conversation.update!(ai_assignee: agent_bot)

      described_class.new(call: call, agent: agent).accept

      expect(conversation.reload.assigned_entity).to eq(agent_bot)
    end

    it 'lets the answering agent claim a call the PBX already reported as answered' do
      call.update!(status: 'in_progress', started_at: 5.seconds.ago)

      described_class.new(call: call, agent: agent).accept

      expect(call.reload).to have_attributes(status: 'in_progress', accepted_by_agent_id: agent.id)
    end

    it 'is idempotent for the agent who already accepted the call' do
      call.update!(status: 'in_progress', accepted_by_agent_id: agent.id, started_at: 5.seconds.ago)

      expect { described_class.new(call: call, agent: agent).accept }.not_to raise_error
    end

    it 'raises AlreadyAccepted when another agent has already accepted the call' do
      other_agent = create(:user, account: account)
      call.update!(status: 'in_progress', accepted_by_agent_id: other_agent.id)

      expect { described_class.new(call: call, agent: agent).accept }
        .to raise_error(StandardError) { |error| expect(error.class.name).to eq('Voice::CallErrors::AlreadyAccepted') }
    end

    it 'raises CallAlreadyEnded when the call has reached a terminal state' do
      call.update!(status: 'completed')

      expect { described_class.new(call: call, agent: agent).accept }
        .to raise_error(StandardError) { |error| expect(error.class.name).to eq('Voice::CallErrors::CallAlreadyEnded') }
    end
  end

  describe '#terminate' do
    it 'completes an in-progress call and records its duration' do
      call.update!(status: 'in_progress', accepted_by_agent_id: agent.id, started_at: 30.seconds.ago)

      described_class.new(call: call, agent: agent).terminate

      expect(call.reload).to have_attributes(status: 'completed', end_reason: 'agent_hangup')
      expect(call.duration_seconds).to be >= 30
      expect(ActionCable.server).to have_received(:broadcast).with(
        "account_#{account.id}", hash_including(event: 'voice_call.ended')
      )
    end

    it 'marks an unanswered outbound call as no_answer' do
      call.update!(direction: :outgoing, accepted_by_agent_id: agent.id)

      described_class.new(call: call, agent: agent).terminate

      expect(call.reload.status).to eq('no_answer')
    end

    it 'leaves a call the PBX already finished untouched' do
      call.update!(status: 'completed', end_reason: 'completed', duration_seconds: 42)

      described_class.new(call: call, agent: agent).terminate

      expect(call.reload).to have_attributes(status: 'completed', end_reason: 'completed', duration_seconds: 42)
    end
  end
end
