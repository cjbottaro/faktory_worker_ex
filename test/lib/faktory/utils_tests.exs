defmodule Faktory.UtilsTests do
  use ExUnit.Case, async: true

  describe "hash_password/3" do
    test "it correctly salts and hashes the password" do
      iterations = 1545
      password = "foobar"
      salt = "55104dc76695721d"

      expected = "6d877f8e5544b1f2598768f817413ab8a357afffa924dedae99eb91472d4ec30"
      actual = Faktory.Utils.hash_password(iterations, password, salt)

      assert expected == actual
    end
  end
end
