# encoding: utf-8

# Testsuite for Wagon.ycp module
#
module Yast
  class WagonTestClient < Client
    def main
      Yast.include self, "testsuite.rb"

      # huh, we need to mock too much paths because of some module constructor... :-(
      @READ = {
        "target"    => {
          "tmpdir" => "/tmp",
          "size"   => 1,
          "stat"   => { "isreg" => true },
          "string" => "SUSE Linux Enterprise Server 11 (x86_64)\n" +
            "VERSION = 11\n" +
            "PATCHLEVEL = 1\n"
        },
        "xml"       => {},
        "sysconfig" => {
          "language" => {
            "RC_LANG"             => "en_US.UTF-8",
            "ROOT_USES_LANG"      => "ctype",
            "RC_LANG"             => "en_US.UTF-8",
            "INSTALLED_LANGUAGES" => ""
          },
          "console"  => { "CONSOLE_ENCODING" => "UTF-8" }
        }
      }

      @EXEC = {
        "target" => {
          "bash_output" => { "exit" => 0, "stdout" => "charmap=\"UTF-8\"\n" }
        }
      }

      TESTSUITE_INIT([@READ, {}, @EXEC], nil)

      Yast.import "Wagon"

      # check parsing registration status file

      # one registered product
      TEST(lambda do
        Wagon.RegistrationStatusFromFile("tests/registration-1product.xml")
      end, [
        [@READ],
        [],
        []
      ], 0)

      # two registered products
      TEST(lambda do
        Wagon.RegistrationStatusFromFile("tests/registration-2products.xml")
      end, [
        [@READ],
        [],
        []
      ], 0)

      # one expired product
      TEST(lambda do
        Wagon.RegistrationStatusFromFile("tests/registration-expired.xml")
      end, [
        [@READ],
        [],
        []
      ], 0)

      # failed registration
      TEST(lambda do
        Wagon.RegistrationStatusFromFile("tests/registration-error.xml")
      end, [
        [@READ],
        [],
        []
      ], 0)

      nil
    end
  end
end

Yast::WagonTestClient.new.main
