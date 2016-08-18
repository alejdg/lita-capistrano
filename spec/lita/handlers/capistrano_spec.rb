require "spec_helper"

describe Lita::Handlers::Capistrano, lita_handler: true do
  it { is_expected.to route ("cap commerce list").to(:cap_list)}
end
