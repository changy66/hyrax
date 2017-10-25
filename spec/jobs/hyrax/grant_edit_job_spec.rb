RSpec.describe Hyrax::GrantEditJob do
  let(:depositor) { create(:user) }
  let(:file_set) { create_for_repository(:file_set) }

  it 'grants a user edit access to a FileSet' do
    expect(file_set.edit_users).not_to include(depositor.user_key)
    described_class.perform_now(file_set.id, depositor.user_key)
    reload = Hyrax::Queries.find_by(id: file_set.id)
    expect(reload.edit_users).to include(depositor.user_key)
  end
end
