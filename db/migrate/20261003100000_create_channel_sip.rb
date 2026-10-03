class CreateChannelSip < ActiveRecord::Migration[7.2]
  # The existence guards keep this runnable on installs that already carry a `channel_sip`
  # table (account_id + url): they only gain the new columns and indexes.
  def change
    create_table :channel_sip, if_not_exists: true do |t|
      t.bigint :account_id, null: false
      t.string :url, null: false
      t.timestamps
    end

    change_table :channel_sip, bulk: true do |t|
      t.string :phone_number unless column_exists?(:channel_sip, :phone_number)
      t.string :webhook_token unless column_exists?(:channel_sip, :webhook_token)
      t.jsonb :provider_config, default: {} unless column_exists?(:channel_sip, :provider_config)
    end

    add_index :channel_sip, :account_id, if_not_exists: true
    add_index :channel_sip, :webhook_token, unique: true, if_not_exists: true
  end
end
