# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InboxMember, type: :model do
  let(:user) { create(:user) }
  let(:inbox) { create(:inbox) }
  let!(:inbox_member) { create(:inbox_member, inbox: inbox, user: user) }

  describe 'audit log' do
    context 'when inbox member is created' do
      it 'has associated audit log created' do
        expect(Audited::Audit.where(auditable: inbox_member, action: 'create').count).to eq(1)
      end

      it 'has user_id in audited_changes matching user.id' do
        audit_log = Audited::Audit.find_by(auditable: inbox_member, action: 'create')
        expect(audit_log.audited_changes['user_id']).to eq(user.id)
      end
    end

    context 'when inbox member is destroyed' do
      it 'has associated audit log created' do
        inbox_member.destroy
        audit_log = Audited::Audit.find_by(auditable: inbox_member, action: 'destroy')
        expect(audit_log).to be_present
        expect(audit_log.audited_changes['inbox_id']).to eq(inbox.id)
      end

      it 'keeps the SIP credentials out of the audit log' do
        inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')
        inbox_member.destroy

        audit_log = Audited::Audit.find_by(auditable: inbox_member, action: 'destroy')
        expect(audit_log.audited_changes).not_to have_key('data')
      end
    end
  end

  describe 'SIP extension' do
    it 'persists the SIP URI and password' do
      inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')

      expect(inbox_member.reload).to have_attributes(sip_uri: 'sip:1001@pbx.example.com', sip_password: 'secret')
    end

    it 'rejects a URI that is not a SIP URI' do
      inbox_member.sip_uri = '1001@pbx.example.com'

      expect(inbox_member).not_to be_valid
    end

    it 'rejects an extension another member of the inbox already has' do
      inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com')
      other_member = create(:inbox_member, inbox: inbox)

      other_member.sip_uri = 'sip:1001@other-pbx.example.com'

      expect(other_member).not_to be_valid
    end

    it 'allows the same extension on another inbox' do
      inbox_member.update!(sip_uri: 'sip:1001@pbx.example.com')

      expect(create(:inbox_member, sip_uri: 'sip:1001@pbx.example.com')).to be_persisted
    end

    it 'extracts the extension from the SIP URI' do
      expect(inbox_member.sip_extension).to be_nil

      inbox_member.sip_uri = 'sip:1001@pbx.example.com'

      expect(inbox_member.sip_extension).to eq('1001')
    end
  end
end
