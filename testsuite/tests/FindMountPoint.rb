# encoding: utf-8

module Yast
  class FindMountPointClient < Client
    def main
      Yast.include self, "testsuite.rb"

      Yast.include self, "wagon/wagon_helpers.rb"

      #import "Wagon";
      DUMP("Test nil")
      TEST(lambda { FindMountPoint(nil, nil) }, [], nil)
      TEST(lambda { FindMountPoint(nil, []) }, [], nil)
      TEST(lambda { FindMountPoint(nil, ["/boot", "/"]) }, [], nil)

      DUMP("Test empty string")
      TEST(lambda { FindMountPoint("", nil) }, [], nil)
      TEST(lambda { FindMountPoint("", []) }, [], nil)
      TEST(lambda { FindMountPoint("", ["/boot", "/"]) }, [], nil)

      DUMP("Test valid values")
      TEST(lambda { FindMountPoint("/", ["/boot", "/", "/usr"]) }, [], nil)
      TEST(lambda { FindMountPoint("/usr", ["/boot", "/", "/usr"]) }, [], nil)
      TEST(lambda { FindMountPoint("/usr/", ["/boot", "/", "/usr"]) }, [], nil)
      TEST(lambda { FindMountPoint("/usr/share/locale", ["/boot", "/", "/usr"]) }, [], nil)
      TEST(lambda do
        FindMountPoint(
          "/usr/share/locale",
          ["/boot", "/", "/usr", "/usr/share"]
        )
      end, [], nil)

      nil
    end
  end
end

Yast::FindMountPointClient.new.main
