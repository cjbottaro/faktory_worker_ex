defprotocol Faktory.Socket do
  @moduledoc false

  def close(socket)
  def active(socket, how)
  def recv(socket, how)
  def send(socket, data)

end
