defmodule Camera do
  use EvercamMedia.Web, :model
  import Ecto.Changeset
  import Ecto.Query
  alias EvercamMedia.Repo
  alias EvercamMedia.Schedule
  alias EvercamMedia.Util

  @mac_address_regex ~r/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/

  @required_fields ~w(name owner_id config is_public is_online_email_owner_notification)
  @optional_fields ~w(exid timezone thumbnail_url is_online last_polled_at last_online_at updated_at created_at model_id location mac_address discoverable)

  schema "cameras" do
    belongs_to :owner, User, foreign_key: :owner_id
    belongs_to :vendor_model, VendorModel, foreign_key: :model_id
    has_many :access_rights, AccessRight
    has_many :shares, CameraShare
    has_one :cloud_recordings, CloudRecording
    has_one :motion_detections, MotionDetection

    field :exid, :string
    field :name, :string
    field :timezone, :string
    field :thumbnail_url, :string
    field :is_online, :boolean
    field :is_public, :boolean, default: false
    field :is_online_email_owner_notification, :boolean, default: false
    field :discoverable, :boolean, default: false
    field :config, EvercamMedia.Types.JSON
    field :mac_address, EvercamMedia.Types.MACADDR
    field :location, Geo.Point
    field :last_polled_at, Ecto.DateTime, default: Ecto.DateTime.utc
    field :last_online_at, Ecto.DateTime, default: Ecto.DateTime.utc
    timestamps(inserted_at: :created_at, type: Ecto.DateTime, default: Ecto.DateTime.utc)
  end

  def all do
    Camera
    |> preload(:cloud_recordings)
    |> preload(:motion_detections)
    |> preload(:vendor_model)
    |> preload([vendor_model: :vendor])
    |> Repo.all
  end

  def all_offline do
    Camera
    |> where(exid: ^"shigan-rjm")
    |> where(is_online: false)
    |> preload(:owner)
    |> Repo.all
  end

  def invalidate_user(nil), do: :noop
  def invalidate_user(%User{} = user) do
    ConCache.delete(:cameras, "#{user.username}_true")
    ConCache.delete(:cameras, "#{user.username}_false")
  end

  def invalidate_camera(nil), do: :noop
  def invalidate_camera(%Camera{} = camera) do
    ConCache.delete(:camera_full, camera.exid)
    ConCache.delete(:camera, camera.exid)
    invalidate_shares(camera)
  end

  defp invalidate_shares(%Camera{} = camera) do
    CameraShare
    |> where(camera_id: ^camera.id)
    |> preload(:user)
    |> Repo.all
    |> Enum.map(fn(cs) -> cs.user end)
    |> Enum.into([camera.owner])
    |> Enum.each(fn(user) -> invalidate_user(user) end)
  end

  def for(user, true), do: owned_by(user) |> Enum.into(shared_with(user))
  def for(user, false), do: owned_by(user)

  defp owned_by(user) do
    Camera
    |> where([cam], cam.owner_id == ^user.id)
    |> preload(:owner)
    |> preload(:cloud_recordings)
    |> preload([vendor_model: :vendor])
    |> Repo.all
  end

  defp shared_with(user) do
    Camera
    |> join(:left, [u], cs in CameraShare)
    |> where([cam, cs], cs.user_id == ^user.id)
    |> where([cam, cs], cam.id == cs.camera_id)
    |> preload(:owner)
    |> preload(:cloud_recordings)
    |> preload([vendor_model: :vendor])
    |> preload([access_rights: :access_token])
    |> Repo.all
  end

  def get(exid) do
    ConCache.dirty_get_or_store(:camera, exid, fn() ->
      Camera.by_exid(exid)
    end)
  end

  def get_full(exid) do
    exid = String.downcase(exid)

    ConCache.dirty_get_or_store(:camera_full, exid, fn() ->
      Camera.by_exid_with_associations(exid)
    end)
  end

  def by_exid(exid) do
    Camera
    |> where(exid: ^exid)
    |> Repo.one
  end

  def by_exid_with_associations(exid) do
    Camera
    |> where([cam], cam.exid == ^String.downcase(exid))
    |> preload(:owner)
    |> preload(:cloud_recordings)
    |> preload(:motion_detections)
    |> preload([vendor_model: :vendor])
    |> preload([access_rights: :access_token])
    |> Repo.one
  end

  def auth(camera) do
    username(camera) <> ":" <> password(camera)
  end

  def username(camera) do
    Util.deep_get(camera, [:config, "auth", "basic", "username"], "")
  end

  def password(camera) do
    Util.deep_get(camera, [:config, "auth", "basic", "password"], "")
  end

  def snapshot_url(camera, type \\ "jpg") do
    cond do
      external_url(camera) != "" && res_url(camera, type) != "" ->
        "#{external_url(camera)}#{res_url(camera, type)}"
      external_url(camera) != "" ->
        "#{external_url(camera)}"
      true ->
        ""
    end
  end

  def external_url(camera, protocol \\ "http") do
    host = host(camera) |> to_string
    port = port(camera, "external", protocol) |> to_string
    case {host, port} do
      {"", _} -> ""
      {host, ""} -> "#{protocol}://#{host}"
      {host, port} -> "#{protocol}://#{host}:#{port}"
    end
  end

  def internal_snapshot_url(camera, type \\ "jpg") do
    case internal_url(camera) != "" && res_url(camera, type) != "" do
      true -> internal_url(camera) <> res_url(camera, type)
      false -> ""
    end
  end

  def internal_url(camera, protocol \\ "http") do
    host = host(camera, "internal") |> to_string
    port = port(camera, "internal", protocol) |> to_string
    case {host, port} do
      {"", _} -> ""
      {host, ""} -> "#{protocol}://#{host}"
      {host, port} -> "#{protocol}://#{host}:#{port}"
    end
  end

  def res_url(camera, type \\ "jpg") do
    url = Util.deep_get(camera, [:config, "snapshots", "#{type}"], "")
    case String.starts_with?(url, "/") || url == "" do
      true -> "#{url}"
      false -> "/#{url}"
    end
  end

  defp url_path(camera, type) do
    cond do
      res_url(camera, type) != "" ->
        res_url(camera, type)
      res_url(camera, type) == "" && get_model_attr(camera, :config) != "" ->
        res_url(camera.vendor_model, type)
      true ->
        ""
    end
  end

  def host(camera, network \\ "external") do
    camera.config["#{network}_host"]
  end

  def port(camera, network, protocol) do
    camera.config["#{network}_#{protocol}_port"]
  end

  def rtsp_url(camera, network \\ "external", type \\ "h264", include_auth \\ true) do
    auth = if include_auth, do: "#{auth(camera)}@", else: ""
    path = url_path(camera, type)
    host = host(camera)
    port = port(camera, network, "rtsp")

    case path != "" && host != "" && "#{port}" != "" && "#{port}" != 0 do
      true -> "rtsp://#{auth}#{host}:#{port}#{path}"
      false -> ""
    end
  end

  def get_rtmp_url(camera) do
    if rtsp_url(camera) != "" do
      base_url = EvercamMedia.Endpoint.url |> String.replace("http", "rtmp") |> String.replace("4000", "1935")
      base_url <> "/live/" <> streaming_token(camera) <> "?camera_id=" <> camera.exid
    else
      ""
    end
  end

  def get_hls_url(camera) do
    if rtsp_url(camera) != "" do
      base_url = EvercamMedia.Endpoint.static_url
      base_url <> "/live/" <> streaming_token(camera) <> "/index.m3u8?camera_id=" <> camera.exid
    else
      ""
    end
  end

  defp streaming_token(camera) do
    token = username(camera) <> "|" <> password(camera) <> "|" <> rtsp_url(camera)
    Util.encode([token])
  end

  def get_vendor_attr(camera_full, attr) do
    case camera_full.vendor_model do
      nil -> ""
      vendor_model -> Map.get(vendor_model.vendor, attr)
    end
  end

  def get_model_attr(camera_full, attr) do
    case camera_full.vendor_model do
      nil -> ""
      vendor_model -> Map.get(vendor_model, attr)
    end
  end

  def get_timezone(camera) do
    case camera.timezone do
      nil -> "Etc/UTC"
      timezone -> timezone
    end
  end

  def get_offset(camera) do
    camera
    |> Camera.get_timezone
    |> Calendar.DateTime.now!
    |> Calendar.Strftime.strftime!("%z")
  end

  def get_mac_address(camera) do
    case camera.mac_address do
      nil -> ""
      mac_address -> mac_address
    end
  end

  def get_location(camera) do
    case camera.location do
      %Geo.Point{coordinates: {lng, lat}} ->
        %{lng: lng, lat: lat}
      _nil ->
        %{lng: 0, lat: 0}
    end
  end

  def get_camera_info(exid) do
    camera = Camera.get(exid)
    %{
      "url" => external_url(camera),
      "auth" => auth(camera)
    }
  end

  def get_rights(camera, user) do
    cond do
      user == nil && camera.is_public ->
        "snapshot,list"
      is_owner?(user, camera) ->
        "snapshot,list,edit,delete,view,grant~snapshot,grant~view,grant~edit,grant~delete,grant~list"
      camera.access_rights == [] ->
        "snapshot,list"
      true ->
        camera.access_rights
        |> Enum.filter(fn(ar) -> Util.deep_get(ar, [:access_token, :user_id], 0) == user.id && ar.status == 1 end)
        |> Enum.map(fn(ar) -> ar.right end)
        |> Enum.into(["snapshot", "list"])
        |> Enum.uniq
        |> Enum.join(",")
    end
  end

  def is_owner?(nil, _camera), do: false
  def is_owner?(user, camera) do
    user.id == camera.owner_id
  end

  def recording?(camera_full) do
    !!Application.get_env(:evercam_media, :start_camera_workers)
    && CloudRecording.sleep(camera_full.cloud_recordings) == 1000
    && Schedule.scheduled_now?(camera_full) == {:ok, true}
  end

  def get_remembrance_camera do
    Camera
    |> where(exid: "evercam-remembrance-camera")
    |> preload(:owner)
    |> Repo.one
  end

  def update_status(camera, status) do
    changeset = changeset(camera, %{is_online: status})
    Repo.update!(changeset)
    invalidate_camera(camera)
  end

  def delete_by_owner(owner_id) do
    Camera
    |> where([cam], cam.owner_id == ^owner_id)
    |> Repo.delete_all
  end

  def delete_by_id(camera_id) do
    Camera
    |> where(id: ^camera_id)
    |> Repo.delete_all
  end

  def validate_params(camera_changeset) do
    timezone = get_field(camera_changeset, :timezone)
    config = get_field(camera_changeset, :config)
    cond do
      config["external_host"] == nil || config["external_host"] == "" ->
        add_error(camera_changeset, :external_host, "can't be blank")
      !valid?("address", config["external_host"]) ->
        add_error(camera_changeset, :external_host, "External url is invalid")
      !is_nil(timezone) && !Tzdata.zone_exists?(timezone) ->
        add_error(camera_changeset, :timezone, "Timezone does not exist or is invalid")
      true ->
        camera_changeset
    end
  end

  def valid?("address", value) do
    valid?("ip_address", value) || valid?("domain", value)
  end

  def valid?("ip_address", value) do
    case :inet_parse.strict_address(to_char_list(value)) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def valid?("domain", value) do
    :inet_parse.domain(to_char_list(value)) && String.contains?(value, ".")
  end

  defp validate_lng_lat(camera_changeset, nil, nil), do: camera_changeset
  defp validate_lng_lat(camera_changeset, _lng, nil), do: add_error(camera_changeset, :location_lat, "Must provide both location coordinates")
  defp validate_lng_lat(camera_changeset, nil, _lat), do: add_error(camera_changeset, :location_lng, "Must provide both location coordinates")
  defp validate_lng_lat(camera_changeset, lng, lat), do: put_change(camera_changeset, :location, %Geo.Point{coordinates: {lng, lat}})

  defp validate_exid(changeset) do
    case get_field(changeset, :exid) do
      nil -> auto_generate_camera_id(changeset)
      _exid -> changeset |> update_change(:exid, &String.downcase/1)
    end
  end

  defp auto_generate_camera_id(changeset) do
    case get_field(changeset, :name) do
      nil ->
        changeset
      camera_name ->
        camera_id =
          camera_name
          |> String.replace(" ", "")
          |> String.replace("-", "")
          |> String.downcase
          |> String.slice(0..4)
        put_change(changeset, :exid, "#{camera_id}-#{Enum.take_random(?a..?z, 5)}")
    end
  end

  def count(query \\ Camera) do
    query
    |> select([cam], count(cam.id))
    |> Repo.one
  end

  def public_cameras_query(coordinates, within_distance) do
    Camera
    |> Camera.where_public_and_discoverable
    |> Camera.by_distance(coordinates, within_distance)
  end

  def get_query_with_associations(query) do
    query
    |> preload(:owner)
    |> preload(:vendor_model)
    |> preload([vendor_model: :vendor])
    |> Repo.all
  end

  def get_query_with_associations(query, limit, offset) do
    query
    |> limit(^limit)
    |> offset(^offset)
    |> preload(:owner)
    |> preload(:vendor_model)
    |> preload([vendor_model: :vendor])
    |> Repo.all
  end

  def where_public_and_discoverable(query \\ Camera) do
    query
    |> where([cam], cam.is_public == true )
    |> where([cam], cam.discoverable == true)
  end

  def by_distance(query \\ Camera, _coordinates, _within_distance)
  def by_distance(query, {0, 0}, _within_distance), do: query
  def by_distance(query, {lng, lat}, within_distance) do
    query
    |> where([cam], fragment("ST_DWithin(?, ST_SetSRID(ST_Point(?, ?), 4326)::geography, CAST(? AS float8))", cam.location, ^lng, ^lat, ^within_distance))
  end

  def where_location_is_not_nil(query \\ Camera) do
    query
    |> where([cam], not(is_nil(cam.location)))
  end

  def delete_changeset(camera, params \\ :invalid) do
    camera
    |> cast(params, @required_fields, @optional_fields)
  end

  def changeset(camera, params \\ :invalid) do
    camera
    |> cast(params, @required_fields, @optional_fields)
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, max: 24, message: "Camera Name is too long. Maximum 24 characters.")
    |> validate_exid
    |> validate_params
    |> unique_constraint(:exid, [name: "cameras_exid_index"])
    |> validate_format(:mac_address, @mac_address_regex, message: "Mac address is invalid")
    |> validate_lng_lat(params[:location_lng], params[:location_lat])
  end
end
