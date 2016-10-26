defmodule EvercamMedia.CameraControllerTest do
  use EvercamMedia.ConnCase
  alias EvercamMedia.Snapshot.Storage

  setup context do
    System.put_env("SNAP_KEY", "aaaaaaaaaaaaaaaa")
    System.put_env("SNAP_IV", "bbbbbbbbbbbbbbbb")

    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    _admin_user = Repo.insert!(%User{firstname: "Admin", lastname: "Admin", username: "admin", email: "admin@evercam.io", password: "password123", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    _access_token1 = Repo.insert!(%AccessToken{user_id: user.id, request: UUID.uuid4(:hex), is_revoked: false})
    user_b = Repo.insert!(%User{firstname: "Smith", lastname: "Marc", username: "smithmarc", email: "smith@dmarc.com", password: "password456", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    _access_token2 = Repo.insert!(%AccessToken{user_id: user_b.id, request: UUID.uuid4(:hex), is_revoked: false})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: %{"external_host" => "192.168.1.100", "external_http_port" => "80"}})
    vendor = Repo.insert!(%Vendor{exid: "other", name: "Other", known_macs: []})
    _vendor_model = Repo.insert!(%VendorModel{vendor_id: vendor.id, name: "Default", exid: "other_default", config: %{}})

    now = Calendar.DateTime.now!("UTC")
    if context[:thumbnail] do
      timestamp = now |> Calendar.DateTime.Format.unix

      Storage.save(camera.exid, timestamp, "test_content", "Test Note")
    end

    {:ok, datetime: now, user: user, camera: camera, user_b: user_b}
  end

  test 'PUT /v1/cameras/:id, returns success and the camera details when given valid parameters', context do
    response =
      build_conn
      |> put("/v1/cameras/#{context[:camera].exid}?user_id=smithmarc&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    camera =
      response.resp_body
      |> Poison.decode!
      |> Map.get("cameras")
      |> List.first

    assert response.status == 200
    assert camera != nil
    assert camera["id"] == context[:camera].exid
    assert camera["owner"] == context[:user_b].username
  end

  test 'PUT /v1/cameras/:id, returns an unauthorized error if the caller is not the camera owner', context do
    response =
      build_conn
      |> put("/v1/cameras/#{context[:camera].exid}?user_id=smithmarc&api_id=#{context[:user_b].api_id}&api_key=#{context[:user_b].api_key}")

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 403
    assert message == "Unauthorized."
  end

  test 'PUT /v1/cameras/:id, returns a not found error for a camera that does not exist', context do
    response =
      build_conn
      |> put("/v1/cameras/cameraxyz?user_id=smithmarc&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 404
    assert message == "The cameraxyz camera does not exist."
  end

  test 'PUT /v1/cameras/:id, returns a not found error when the new owner does not exist', context do
    response =
      build_conn
      |> put("/v1/cameras/#{context[:camera].exid}?user_id=userxyz&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 404
    assert message == "User 'userxyz' does not exist."
  end

  test 'PUT /v1/cameras/:id, returns an unauthenticated error when no authentication details are provided' do
    response =
      build_conn
      |> put("/v1/cameras/austin?user_id=smithmarc")

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 401
    assert message == "Unauthorized."
  end

  test 'PATCH /v1/cameras/:id, returns success and the camera details when given valid parameters', context do
    camera_params = %{
      name: "Rename Camera",
      external_host: "212.78.102.10",
      external_rtsp_port: "8100",
      external_http_port: "8100",
      vendor: "hikvision",
      is_public: "true"
    }
    response =
      build_conn
      |> patch("/v1/cameras/#{context[:camera].exid}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", camera_params)

    camera =
      response.resp_body
      |> Poison.decode!
      |> Map.get("cameras")
      |> List.first

    assert response.status == 200
    assert camera != nil
    assert camera["id"] == context[:camera].exid
    assert camera["name"] == camera_params[:name]
    assert camera["external"]["host"] == camera_params[:external_host]
    assert camera["external"]["http"]["port"] == camera_params[:external_http_port]
  end

  test 'PATCH /v1/cameras/:id, returns a not found error for a camera that does not exist', context do
    response =
      build_conn
      |> patch("/v1/cameras/cameraxyz?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", %{})

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 404
    assert message == "The cameraxyz camera does not exist."
  end

  test 'PATCH /v1/cameras/:id, returns Unauthorized error when user does not have permissions', context do
    camera_params = %{
      name: "Rename Camera"
    }
    response =
      build_conn
      |> patch("/v1/cameras/#{context[:camera].exid}?api_id=#{context[:user_b].api_id}&api_key=#{context[:user_b].api_key}", camera_params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 403
    assert message == "Unauthorized."
  end

  test 'PATCH /v1/cameras/:id, returns error when passed invalid params', context do
    camera_params = %{
      external_host: "Rename Camera"
    }
    response =
      build_conn
      |> patch("/v1/cameras/#{context[:camera].exid}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", camera_params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")
      |> Map.get("external_host")

    assert response.status == 400
    assert message == ["External url is invalid"]
  end

  @tag :skip
  test 'DELETE /v1/cameras/:id, returns success when camera and all associations delete', context do
    delete_response =
      build_conn
      |> delete("/v1/cameras/#{context[:camera].exid}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")
    get_response =
      build_conn
      |> get("/v1/cameras/#{context[:camera].exid}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert delete_response.status == 200
    assert delete_response.resp_body == "{}"
    assert get_response.status == 404
  end

  test 'DELETE /v1/cameras/:id, returns an unauthenticated error when no authentication details are provided' do
    response =
      build_conn
      |> delete("/v1/cameras/austin")

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 403
    assert message == "Unauthorized."
  end

  test 'DELETE /v1/cameras/:id, returns Unauthorized error when user does not have permissions', context do
    response =
      build_conn
      |> delete("/v1/cameras/#{context[:camera].exid}?api_id=#{context[:user_b].api_id}&api_key=#{context[:user_b].api_key}")

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 403
    assert message == "Unauthorized."
  end

  test 'POST /v1/cameras, returns camera when the params are valid', context do
    camera_params = %{
      name: "Camera Name",
      external_host: "212.78.102.10"
    }

    response =
      build_conn
      |> post("/v1/cameras?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", camera_params)

    camera =
      response.resp_body
      |> Poison.decode!
      |> Map.get("cameras")
      |> List.first

    assert response.status == 201
    assert camera != nil
    assert camera["name"] == camera_params[:name]
    assert camera["external"]["host"] == camera_params[:external_host]
  end

  test 'POST /v1/cameras, when external_url is missing', context do
    camera_params = %{
      name: "Rename Camera"
    }

    response =
      build_conn
      |> post("/v1/cameras?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", camera_params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")
      |> Map.get("external_host")

    assert response.status == 400
    assert message == ["can't be blank"]
  end

  test 'POST /v1/cameras, returns Unauthorized error when user does not have permissions' do
    camera_params = %{
      name: "Rename Camera",
      external_host: "212.78.102.10"
    }

    response =
      build_conn
      |> post("/v1/cameras", camera_params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 401
    assert message == "Unauthorized."
  end

  test 'POST /v1/cameras, returns error when passed invalid params', context do
    camera_params = %{
      name: "Camera Name",
      external_host: "Rename Camera"
    }
    response =
      build_conn
      |> post("/v1/cameras?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", camera_params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")
      |> Map.get("external_host")

    assert response.status == 400
    assert message == ["External url is invalid"]
  end
end
