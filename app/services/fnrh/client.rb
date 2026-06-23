module Fnrh
  class Client
    def self.build(filial)
      return MockClient.new(filial) if Configuration.mock?

      RealClient.new(filial)
    end
  end
end
