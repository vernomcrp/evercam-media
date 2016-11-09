defmodule EvercamMedia.UserMailer do
  alias EvercamMedia.Snapshot.Storage

  @config Application.get_env(:evercam_media, :mailgun)
  @from Application.get_env(:evercam_media, EvercamMedia.Endpoint)[:email]
  @year Calendar.DateTime.now_utc |> Calendar.Strftime.strftime!("%Y")

  def confirm(user, code) do
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "Evercam Confirmation",
      from: @from,
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "confirm.html", user: user, code: code, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "confirm.txt", user: user, code: code)
  end

  def camera_status(status, user, camera) do
    timezone = camera |> Camera.get_timezone
    current_time = Calendar.DateTime.now_utc |> Calendar.DateTime.shift_zone!(timezone) |> Calendar.Strftime.strftime!("%A, %d %b %Y %l:%M %p")
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "\"#{camera.name}\" camera is now #{status}",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "#{status}.html", user: user, camera: camera, thumbnail_available: !!thumbnail, year: @year, current_time: current_time),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "#{status}.txt", user: user, camera: camera)
  end

  def camera_offline_reminder(user, camera, subject) do
    timezone = camera |> Camera.get_timezone
    current_time =
      camera.last_online_at
      |> Ecto.DateTime.to_erl
      |> Calendar.DateTime.from_erl!("UTC")
      |> Calendar.DateTime.shift_zone!(timezone)
      |> Calendar.Strftime.strftime!("%A, %d %b %Y %l:%M %p")
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "#{subject} reminder: \"#{camera.name}\" camera has gone offline",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "offline.html", user: user, camera: camera, thumbnail_available: !!thumbnail, year: @year, current_time: current_time),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "offline.txt", user: user, camera: camera)
  end

  def camera_shared_notification(user, camera, sharee_email, message) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: sharee_email,
      subject: "#{User.get_fullname(user)} has shared a camera with you",
      from: @from,
      "h:Reply-To": user.email,
      bcc: user.email,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "camera_shared_notification.html", user: user, camera: camera, message: message, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "camera_shared_notification.txt", user: user, camera: camera, message: message)
  end

  def camera_share_request_notification(user, camera, email, message, key) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: email,
      subject: "#{User.get_fullname(user)} has shared a camera with you",
      from: @from,
      "h:Reply-To": user.email,
      bcc: user.email,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "sign_up_to_share_email.html", user: user, camera: camera, message: message, key: key, sharee: email, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "sign_up_to_share_email.txt", user: user, camera: camera, message: message, key: key)
  end

  def accepted_share_request_notification(user, camera, email) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "#{email} has accepted your request to view your camera",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "accepted_share_request.html", user: user, camera: camera, sharee: email, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "accepted_share_request.txt", user: user, camera: camera, sharee: email)
  end

  def revoked_share_request_notification(user, camera, email) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "#{email} did not accept your request to view your camera",
      from: @from,
      bcc: "marco@evercam.io,vinnie@evercam.io",
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "revoke_share_request.html", user: user, camera: camera, sharee: email, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "revoke_share_request.txt", user: user, camera: camera, sharee: email)
  end

  def camera_create_notification(user, camera) do
    thumbnail = get_thumbnail(camera)
    Mailgun.Client.send_email @config,
      to: user.email,
      subject: "A new camera has been added to your account",
      from: @from,
      bcc: "marco@evercam.io,vinnie@evercam.io",
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "camera_create_notification.html", user: user, camera: camera, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "camera_create_notification.txt", user: user, camera: camera)
  end

  def archive_completed(archive, email) do
    thumbnail = get_thumbnail(archive.camera)
    Mailgun.Client.send_email @config,
      to: email,
      subject: "Archive #{archive.title} is ready.",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "archive_create_completed.html", archive: archive, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "archive_create_completed.txt", archive: archive, thumbnail_available: !!thumbnail, year: @year)
  end

  def archive_failed(archive, email) do
    thumbnail = get_thumbnail(archive.camera)
    Mailgun.Client.send_email @config,
      to: email,
      subject: "Archive #{archive.title} is failed.",
      from: @from,
      attachments: get_attachments(thumbnail),
      html: Phoenix.View.render_to_string(EvercamMedia.EmailView, "archive_create_failed.html", archive: archive, thumbnail_available: !!thumbnail, year: @year),
      text: Phoenix.View.render_to_string(EvercamMedia.EmailView, "archive_create_failed.txt", archive: archive, thumbnail_available: !!thumbnail, year: @year)
  end

  defp get_thumbnail(camera) do
    case Storage.thumbnail_load(camera.exid) do
      {:ok, image} -> image
      _ -> nil
    end
  end

  defp get_attachments(thumbnail) do
    if thumbnail, do: [%{content: thumbnail, filename: "snapshot.jpg"}], else: nil
  end
end
