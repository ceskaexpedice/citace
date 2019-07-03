class CreateLogs < ActiveRecord::Migration[5.1]
  def change
    create_table :logs do |t|
      t.datetime :timestamp
      t.string :kramerius
      t.string :uuid
      t.string :citation
      t.string :model
      t.string :root_model
      t.string :format
    end
  end
end
