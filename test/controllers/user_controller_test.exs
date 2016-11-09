defmodule EvercamMedia.UserControllerTest do
  alias EvercamMedia.Util
  use EvercamMedia.ConnCase

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "smt"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: Comeonin.Bcrypt.hashpwsalt("password123"), api_id: UUID.uuid4(:hex) |> String.slice(0..8), api_key: UUID.uuid4(:hex), country_id: country.id})
    user_evercam = Repo.insert!(%User{firstname: "Evercam", lastname: "Admin", username: "evercam", email: "admin@evercam.io", password: Comeonin.Bcrypt.hashpwsalt("password123"), api_id: UUID.uuid4(:hex) |> String.slice(0..8), api_key: UUID.uuid4(:hex), country_id: country.id})
    camera = Repo.insert!(%Camera{owner_id: user_evercam.id, name: "Herbst Wicklow Camera", exid: "evercam-remembrance-camera", is_public: false, config: %{"external_host" => "192.168.1.100", "external_http_port" => "80"}})
    share_request = Repo.insert!(%CameraShareRequest{camera_id: camera.id, user_id: user.id, key: UUID.uuid4(:hex), email: "legend@john.com", status: -1, rights: "list,snapshot"})

    params = %{
      username: "johndoee",
      email: "legend@john.com",
      firstname: "John",
      lastname: "Legend",
      password: "johnlegend123",
      country: "smt",
      token: "tokenvalue"
    }

    {:ok, user: user, params: params, share_request: share_request}
  end

  test "GET /v1/users/:id when user not found!", context do
    username = "legend"
    response = build_conn |> get("/v1/users/#{username}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")
    response_body = %{"message" => "User does not exist."}

    assert response.status == 404
    assert Poison.decode!(response.resp_body) == response_body
  end

  test "GET /v1/users/:id/credentials Get users credentials", context do
    password = "password123"
    response = build_conn |> get("/v1/users/#{context[:user].username}/credentials?password=#{password}")

    assert response.status == 200
  end

  test "POST /v1/users/ when country is invalid!" do
    params = %{
      country: "pki",
      token: "tokenvalue"
    }
    response =
      build_conn()
      |> post("/v1/users", params)

    response_body = %{"message" => "Country isn't valid!"}

    assert response.status == 400
    assert Poison.decode!(response.resp_body) == response_body
  end

  test "PATCH /v1/users/ when email is not valid while update!", context do
    params = %{email: "test @test.com"}

    expected_error = %{email: ["Email format isn't valid!"]}

    changeset = User.changeset(context[:user], params)
    error = Util.parse_changeset(changeset)

    assert error == expected_error
  end

  test "POST /v1/users when user created successfully!", context do
    response =
      build_conn()
      |> post("/v1/users", context[:params])

    assert response.status == 201
  end

  test "POST /v1/users when user is being created from share request key!", context do
    params = Map.merge(context[:params], %{share_request_key: context[:share_request].key})
    response =
      build_conn()
      |> post("/v1/users", params)

    signed_up_user =
      response.resp_body
      |> Poison.decode!
      |> Map.get("users")
      |> List.first

    assert response.status == 201
    assert signed_up_user["confirmed_at"] != nil
  end

  test "POST /v1/users/:username when user's password is not valid!" do
    user_params =
      %{
          username: "testuser",
          email: "test@email.com",
          firstname: "test",
          lastname: "user",
          password: "123",
          token: "tokenvalue"
      }

    response =
      build_conn()
      |> post("/v1/users/", user_params)

    error =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert error["password"] == ["Password should be at least 6 character(s)."]
    assert response.status == 400
  end

  test "PATCH /v1/users/:username when user updated successfully!", context do
    updated_params = %{email: "doe@john.com", firstname: "Doe", lastname: "John"}
    response =
      build_conn()
      |> patch("/v1/users/#{context[:user].username}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", updated_params)

    updated_user =
      response.resp_body
      |> Poison.decode!
      |> Map.get("users")
      |> List.first

    assert response.status == 200
    assert updated_user["email"] == "doe@john.com"
    assert updated_user["firstname"] == "Doe"
    assert updated_user["lastname"] == "John"
  end
end
