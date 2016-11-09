defmodule EvercamMedia.OfflinePeriodicReminder do
  @moduledoc """
  Provides functions for getting all offline cameras and send reminder to users

  after 1, 2 and 7 days.
  """
  require Logger

  def offline_cameras_reminder do
    Camera.all_offline
    |> Enum.map(&(can_send_reminder &1, &1.is_online_email_owner_notification, &1.last_online_at))
  end

  defp can_send_reminder(_camera, _is_send, nil), do: :noop
  defp can_send_reminder(_camera, false, _last_online_at), do: :noop
  defp can_send_reminder(camera, true, _last_online_at) do
    current_date = Calendar.DateTime.now!("UTC")
    last_online_date =
      camera.last_online_at
      |> Ecto.DateTime.to_erl
      |> Calendar.DateTime.from_erl!("UTC")

    case Calendar.DateTime.diff(current_date, last_online_date) do
      {:ok, seconds, _, :after} -> do_send_notification(camera, seconds)
      _ -> 0
    end
  end

  defp do_send_notification(camera, seconds) when seconds < 608_500 do
    cond do
      seconds >= 86_400 && seconds < 90_000 ->
        EvercamMedia.UserMailer.camera_offline_reminder(camera.owner, camera)
      seconds >= 172_800 && seconds < 176_400 ->
        EvercamMedia.UserMailer.camera_offline_reminder(camera.owner, camera)
      seconds >= 604_800 && seconds < 608_400 ->
        EvercamMedia.UserMailer.camera_offline_reminder(camera.owner, camera)
      true ->
        ""
    end
  end
  defp do_send_notification(_camera, _seconds), do: :noop
end
