defmodule AshJsonApi.JsonSchema do
  @moduledoc false
  alias Ash.Query.Aggregate

  def generate(apis) do
    schema_id = "autogenerated_ash_json_api_schema"

    {definitions, route_schemas} =
      Enum.reduce(apis, {base_definitions(), []}, fn api, {definitions, schemas} ->
        resources =
          api
          |> Ash.Api.Info.resources()
          |> Enum.filter(&AshJsonApi.Resource.Info.type(&1))

        new_route_schemas =
          Enum.flat_map(resources, fn resource ->
            resource
            |> AshJsonApi.Resource.Info.routes()
            |> Enum.map(&route_schema(&1, api, resource))
          end)

        new_definitions =
          Enum.reduce(resources, definitions, fn resource, acc ->
            Map.put(
              acc,
              AshJsonApi.Resource.Info.type(resource),
              resource_object_schema(resource)
            )
          end)

        {new_definitions, new_route_schemas ++ schemas}
      end)

    %{
      "$schema" => "http://json-schema.org/draft-06/schema#",
      "$id" => schema_id,
      "definitions" => definitions,
      "links" => route_schemas
    }
  end

  def route_schema(%{method: method} = route, api, resource) when method in [:delete, :get] do
    {href, properties} = route_href(route, api)

    {href_schema, query_param_string} = href_schema(route, api, resource, properties)

    %{
      "href" => href <> query_param_string,
      "hrefSchema" => href_schema,
      "description" => "pending",
      "method" => route.method |> to_string() |> String.upcase(),
      "rel" => to_string(route.type),
      "targetSchema" => target_schema(route, api, resource),
      "headerSchema" => header_schema()
    }
  end

  def route_schema(route, api, resource) do
    {href, properties} = route_href(route, api)

    {href_schema, query_param_string} = href_schema(route, api, resource, properties)

    %{
      "href" => href <> query_param_string,
      "hrefSchema" => href_schema,
      "description" => "pending",
      "method" => route.method |> to_string() |> String.upcase(),
      "rel" => to_string(route.type),
      "schema" => route_in_schema(route, api, resource),
      "targetSchema" => target_schema(route, api, resource),
      "headerSchema" => header_schema()
    }
  end

  defp header_schema do
    # For the content type header - I think we need a regex such as /^(application/vnd.api\+json;?)( profile=[^=]*";)?$/
    # This will ensure that it starts with "application/vnd.api+json" and only includes a profile param
    # I'm sure there will be a ton of edge cases so we may need to make a utility function for this and add unit tests

    # Here are some scenarios we should test:

    # application/vnd.api+json
    # application/vnd.api+json;
    # application/vnd.api+json; charset=\"utf-8\"
    # application/vnd.api+json; profile=\"utf-8\"
    # application/vnd.api+json; profile=\"utf-8\"; charset=\"utf-8\"
    # application/vnd.api+json; profile="foo"; charset=\"utf-8\"
    # application/vnd.api+json; profile="foo"
    # application/vnd.api+json; profile="foo8"
    # application/vnd.api+json; profile="foo";
    # application/vnd.api+json; profile="foo"; charset="bar"
    # application/vnd.api+json; profile="foo;";
    # application/vnd.api+json; profile="foo

    %{
      "type" => "object",
      "properties" => %{
        "content-type" => %{
          "type" => "array",
          "items" => %{
            "type" => "string"
          }
        },
        "accept" => %{
          "type" => "array",
          "items" => %{
            "type" => "string"
          }
        }
      },
      "additionalProperties" => true
    }
  end

  # This is for our representation of a resource *in the response*
  def resource_object_schema(resource) do
    %{
      "description" =>
        "A \"Resource object\" representing a #{AshJsonApi.Resource.Info.type(resource)}",
      "type" => "object",
      "required" => ["type", "id"],
      "properties" => %{
        "type" => %{
          "additionalProperties" => false
        },
        "id" => %{
          "type" => "string"
        },
        "attributes" => attributes(resource),
        "relationships" => relationships(resource)
        # "meta" => %{
        #   "$ref" => "#/definitions/meta"
        # }
      },
      "additionalProperties" => false
    }
  end

  defp base_definitions do
    %{
      "links" => %{
        "type" => "object",
        "additionalProperties" => %{
          "$ref" => "#/definitions/link"
        }
      },
      "link" => %{
        "description" =>
          "A link **MUST** be represented as either: a string containing the link's URL or a link object.",
        "type" => "string"
      },
      "errors" => %{
        "type" => "array",
        "items" => %{
          "$ref" => "#/definitions/error"
        },
        "uniqueItems" => true
      },
      "error" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{
            "description" => "A unique identifier for this particular occurrence of the problem.",
            "type" => "string"
          },
          "links" => %{
            "$ref" => "#/definitions/links"
          },
          "status" => %{
            "description" =>
              "The HTTP status code applicable to this problem, expressed as a string value.",
            "type" => "string"
          },
          "code" => %{
            "description" => "An application-specific error code, expressed as a string value.",
            "type" => "string"
          },
          "title" => %{
            "description" =>
              "A short, human-readable summary of the problem. It **SHOULD NOT** change from occurrence to occurrence of the problem, except for purposes of localization.",
            "type" => "string"
          },
          "detail" => %{
            "description" =>
              "A human-readable explanation specific to this occurrence of the problem.",
            "type" => "string"
          },
          "source" => %{
            "type" => "object",
            "properties" => %{
              "pointer" => %{
                "description" =>
                  "A JSON Pointer [RFC6901] to the associated entity in the request document [e.g. \"/data\" for a primary data object, or \"/data/attributes/title\" for a specific attribute].",
                "type" => "string"
              },
              "parameter" => %{
                "description" => "A string indicating which query parameter caused the error.",
                "type" => "string"
              }
            }
          }
          # "meta" => %{
          #   "$ref" => "#/definitions/meta"
          # }
        },
        "additionalProperties" => false
      }
    }
  end

  defp attributes(resource) do
    %{
      "description" => "An attributes object for a #{AshJsonApi.Resource.Info.type(resource)}",
      "type" => "object",
      "required" => required_attributes(resource),
      "properties" => resource_attributes(resource),
      "additionalProperties" => false
    }
  end

  defp required_attributes(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.reject(&(&1.allow_nil? || &1.name == :id))
    |> Enum.map(&to_string(&1.name))
  end

  defp resource_attributes(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.reject(&(&1.name == :id))
    |> Enum.reduce(%{}, fn attr, acc ->
      Map.put(acc, to_string(attr.name), resource_attribute_type(attr))
    end)
  end

  defp relationships(resource) do
    %{
      "description" => "A relationships object for a #{AshJsonApi.Resource.Info.type(resource)}",
      "type" => "object",
      "properties" => resource_relationships(resource),
      "additionalProperties" => false
    }
  end

  defp resource_relationships(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(fn relationship ->
      AshJsonApi.Resource.Info.type(relationship)
    end)
    |> Enum.reduce(%{}, fn rel, acc ->
      data = resource_relationship_field_data(resource, rel)
      links = resource_relationship_link_data(resource, rel)

      object =
        if links do
          %{"data" => data, "links" => links}
        else
          %{"data" => data}
        end

      Map.put(
        acc,
        to_string(rel.name),
        object
      )
    end)
  end

  defp resource_relationship_link_data(_resource, _rel) do
    nil
  end

  defp resource_relationship_field_data(_resource, %{
         type: {:array, _},
         name: name
       }) do
    %{
      "description" => "Input for #{name}",
      "anyOf" => [
        %{
          "type" => "null"
        },
        %{
          "description" => "Identifiers for #{name}",
          "type" => "object",
          "required" => ["type", "id"],
          "additionalProperties" => false,
          "properties" => %{
            "type" => %{"type" => "string"},
            "id" => %{"type" => "string"},
            "meta" => %{
              "type" => "object",
              "required" => [],
              "additionalProperties" => true
            }
          }
        }
      ]
    }
  end

  defp resource_relationship_field_data(_resource, %{
         name: name
       }) do
    %{
      "description" => "An array of inputs for #{name}",
      "type" => "array",
      "items" => %{
        "description" => "Resource identifiers for #{name}",
        "type" => "object",
        "required" => ["type", "id"],
        "properties" => %{
          "type" => %{"type" => "string"},
          "id" => %{"type" => "string"},
          "meta" => %{
            "type" => "object",
            "required" => [],
            "additionalProperties" => true
          }
        }
      },
      "uniqueItems" => true
    }
  end

  defp resource_attribute_type(%{type: Ash.Type.String}) do
    %{
      "type" => "string"
    }
  end

  defp resource_attribute_type(%{type: Ash.Type.Boolean}) do
    %{
      "type" => ["boolean", "string"],
      "match" => "^(true|false)$"
    }
  end

  defp resource_attribute_type(%{type: Ash.Type.Integer}) do
    %{
      "type" => ["integer", "string"],
      "match" => "^[1-9][0-9]*$"
    }
  end

  defp resource_attribute_type(%{type: Ash.Type.UtcDatetime}) do
    %{
      "type" => "string",
      "format" => "date-time"
    }
  end

  defp resource_attribute_type(%{type: Ash.Type.UUID}) do
    %{
      "type" => "string",
      "format" => "uuid"
    }
  end

  defp resource_attribute_type(%{type: {:array, type}}) do
    %{
      "type" => "array",
      "items" => resource_attribute_type(%{type: type})
    }
  end

  defp resource_attribute_type(%{type: type} = attr) do
    if :erlang.function_exported(type, :json_schema, 1) do
      if Map.get(attr, :constraints) do
        type.json_schema(attr.constraints)
      else
        type.json_schema([])
      end
    else
      %{
        "type" => "any"
      }
    end
  end

  defp href_schema(route, api, resource, required_properties) do
    base_properties =
      Enum.into(required_properties, %{}, fn prop ->
        {prop, %{"type" => "string"}}
      end)

    {query_param_properties, query_param_string, required} =
      query_param_properties(route, api, resource, required_properties)

    {%{
       "required" => required_properties ++ required,
       "properties" => Map.merge(query_param_properties, base_properties)
     }, query_param_string}
  end

  defp query_param_properties(%{type: :index} = route, api, resource, properties) do
    %{
      "filter" => %{
        "type" => "object",
        "properties" => filter_props(resource)
      },
      "sort" => %{
        "type" => "string",
        "format" => sort_format(resource)
      },
      "page" => %{
        "type" => "object",
        "properties" => page_props(api, resource)
      },
      "include" => %{
        "type" => "string",
        "format" => include_format(resource)
      }
    }
    |> Map.merge(Map.new(properties, &{&1, %{"type" => "any"}}))
    |> add_read_arguments(route, resource)
    |> with_keys()
  end

  defp query_param_properties(%{type: type}, _, resource, properties)
       when type in [:post_to_relationship, :patch_relationship, :delete_from_relationship] do
    %{}
    |> add_route_properties(resource, properties)
    |> with_keys()
  end

  defp query_param_properties(route, _api, resource, properties) do
    props = %{
      "include" => %{
        "type" => "string",
        "format" => include_format(resource)
      }
    }

    if route.type in [:get, :related] do
      props
      |> add_route_properties(resource, properties)
      |> add_read_arguments(route, resource)
      |> with_keys()
    else
      with_keys(props)
    end
  end

  defp add_route_properties(keys, resource, properties) do
    Enum.reduce(properties, keys, fn property, keys ->
      spec =
        if attribute = Ash.Resource.Info.public_attribute(resource, property) do
          resource_attribute_type(attribute)
        else
          %{"type" => "any"}
        end

      Map.put(keys, property, spec)
    end)
  end

  defp add_read_arguments(props, route, resource) do
    action = Ash.Resource.Info.action(resource, route.action, :read)

    {
      action.arguments
      |> Enum.reject(& &1.private?)
      |> Enum.reduce(props, fn argument, props ->
        Map.put(props, to_string(argument.name), attribute_filter_schema(argument.type))
      end),
      action.arguments |> Enum.reject(&(&1.allow_nil? || &1.private?)) |> Enum.map(&"#{&1.name}")
    }
  end

  defp with_keys({map, required}) do
    {map, "{" <> Enum.map_join(map, ",", &elem(&1, 0)) <> "}", required}
  end

  defp with_keys(map) do
    {map, "{" <> Enum.map_join(map, ",", &elem(&1, 0)) <> "}", []}
  end

  defp sort_format(resource) do
    sorts =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.flat_map(fn attr -> [attr.name, "-#{attr.name}"] end)

    "(#{Enum.join(sorts, "|")}),*"
  end

  defp page_props(_api, _resource) do
    %{
      "limit" => %{
        "type" => "string",
        "pattern" => "^[0-9]*$"
      },
      "offset" => %{
        "type" => "string",
        "pattern" => "^[0-9]*$"
      }
    }
  end

  defp include_format(_resource) do
    "pending"
  end

  defp filter_props(resource) do
    acc =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.reduce(%{}, fn attr, acc ->
        Map.put(acc, to_string(attr.name), attribute_filter_schema(attr.type))
      end)

    acc =
      resource
      |> Ash.Resource.Info.public_relationships()
      |> Enum.reduce(acc, fn rel, acc ->
        Map.put(acc, to_string(rel.name), relationship_filter_schema(rel))
      end)

    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Enum.reduce(acc, fn agg, acc ->
      field_type =
        if agg.field do
          related = Ash.Resource.Info.related(resource, agg.relationship_path)
          field = Ash.Resource.Info.field(related, agg.field)

          if field do
            field.type
          end
        end

      {:ok, type} = Aggregate.kind_to_type(agg.kind, field_type)
      Map.put(acc, to_string(agg.name), attribute_filter_schema(type))
    end)
  end

  defp attribute_filter_schema(type) do
    if Ash.Type.embedded_type?(type) do
      %{
        "type" => "any"
      }
    else
      case type do
        Ash.Type.UUID ->
          %{
            "type" => "string",
            "format" => "uuid"
          }

        Ash.Type.String ->
          %{
            "type" => "string"
          }

        Ash.Type.Boolean ->
          %{
            "type" => ["boolean", "string"],
            "match" => "^(true|false)$"
          }

        Ash.Type.Integer ->
          %{
            "type" => ["integer", "string"],
            "match" => "^[1-9][0-9]*$"
          }

        Ash.Type.UtcDateTime ->
          %{
            "type" => "string",
            "format" => "date-time"
          }

        {:array, _type} ->
          %{
            "type" => "any"
          }

        _ ->
          %{
            "type" => "any"
          }
      end
    end
  end

  defp relationship_filter_schema(_rel) do
    %{
      "type" => "string"
    }
  end

  defp route_in_schema(%{type: type}, _api, _resource) when type in [:index, :get, :delete] do
    %{}
  end

  defp route_in_schema(
         %{
           type: type,
           action: action,
           relationship_arguments: relationship_arguments
         },
         _api,
         resource
       )
       when type in [:post] do
    action = Ash.Resource.Info.action(resource, action)

    non_relationship_arguments =
      Enum.reject(action.arguments, &has_relationship_argument?(relationship_arguments, &1.name))

    %{
      "type" => "object",
      "required" => ["data"],
      "additionalProperties" => false,
      "properties" => %{
        "data" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "type" => %{
              "const" => AshJsonApi.Resource.Info.type(resource)
            },
            "attributes" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" =>
                required_write_attributes(resource, non_relationship_arguments, action.accept),
              "properties" =>
                write_attributes(resource, non_relationship_arguments, action.accept)
            },
            "relationships" => %{
              "type" => "object",
              "required" =>
                required_relationship_attributes(resource, relationship_arguments, action),
              "additionalProperties" => false,
              "properties" => write_relationships(resource, relationship_arguments, action)
            }
          }
        }
      }
    }
  end

  defp route_in_schema(
         %{
           type: type,
           action: action,
           relationship_arguments: relationship_arguments
         },
         _api,
         resource
       )
       when type in [:patch] do
    action = Ash.Resource.Info.action(resource, action)

    non_relationship_arguments =
      Enum.reject(action.arguments, &has_relationship_argument?(relationship_arguments, &1.name))

    %{
      "type" => "object",
      "required" => ["data"],
      "additionalProperties" => false,
      "properties" => %{
        "data" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "id" => resource_attribute_type(Ash.Resource.Info.public_attribute(resource, :id)),
            "type" => %{
              "const" => AshJsonApi.Resource.Info.type(resource)
            },
            "attributes" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" =>
                non_relationship_arguments
                |> Enum.reject(& &1.allow_nil?)
                |> Enum.map(&to_string(&1.name)),
              "properties" =>
                write_attributes(resource, non_relationship_arguments, action.accept)
            },
            "relationships" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" =>
                required_relationship_attributes(resource, relationship_arguments, action),
              "properties" => write_relationships(resource, relationship_arguments, action)
            }
          }
        }
      }
    }
  end

  defp route_in_schema(
         %{type: type, relationship: relationship},
         _api,
         resource
       )
       when type in [:post_to_relationship, :patch_relationship, :delete_from_relationship] do
    case Ash.Resource.Info.public_relationship(resource, relationship) do
      nil ->
        raise ArgumentError, """
        Expected resource  #{resource} to define relationship #{relationship} of type #{type}

        Please verify all json_api relationship routes have relationships
        """

      other ->
        relationship_resource_identifiers(other)
    end
  end

  defp relationship_resource_identifiers(relationship) when is_map(relationship) do
    %{
      "type" => "object",
      "required" => ["data"],
      "additionalProperties" => false,
      "properties" => %{
        "data" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["id", "type"],
            "additionalProperties" => false,
            "properties" => %{
              "id" =>
                resource_attribute_type(
                  Ash.Resource.Info.public_attribute(relationship.destination, :id)
                ),
              "type" => %{
                "const" => AshJsonApi.Resource.Info.type(relationship.destination)
              },
              "meta" => %{
                "type" => "object"
                #   "properties" => join_attribute_properties(relationship),
                #   "additionalProperties" => false
              }
            }
          }
        }
      }
    }
  end

  defp required_write_attributes(resource, arguments, accept) do
    attributes =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.filter(&((is_nil(accept) || &1.name in accept) && &1.writable?))
      |> Enum.reject(&(&1.allow_nil? || &1.default || &1.generated?))
      |> Enum.map(&to_string(&1.name))

    arguments =
      arguments
      |> Enum.reject(& &1.allow_nil?)
      |> Enum.map(&to_string(&1.name))

    attributes ++ arguments
  end

  defp write_attributes(resource, arguments, accept) do
    attributes =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.filter(&((is_nil(accept) || &1.name in accept) && &1.writable?))
      |> Enum.reduce(%{}, fn attribute, acc ->
        Map.put(acc, to_string(attribute.name), resource_attribute_type(attribute))
      end)

    Enum.reduce(arguments, attributes, fn argument, attributes ->
      Map.put(attributes, to_string(argument.name), resource_attribute_type(argument))
    end)
  end

  defp required_relationship_attributes(_resource, relationship_arguments, action) do
    action.arguments
    |> Enum.filter(&has_relationship_argument?(relationship_arguments, &1.name))
    |> Enum.reject(& &1.allow_nil?)
    |> Enum.map(&to_string(&1.name))
  end

  defp write_relationships(resource, relationship_arguments, action) do
    action.arguments
    |> Enum.filter(&has_relationship_argument?(relationship_arguments, &1.name))
    |> Enum.reduce(%{}, fn argument, acc ->
      data = resource_relationship_field_data(resource, argument)

      object = %{"data" => data, "links" => %{"type" => "any"}}

      Map.put(
        acc,
        to_string(argument.name),
        object
      )
    end)
  end

  defp has_relationship_argument?(relationship_arguments, name) do
    Enum.any?(relationship_arguments, fn
      {:id, ^name} -> true
      ^name -> true
      _ -> false
    end)
  end

  defp target_schema(route, _api, resource) do
    case route.type do
      :index ->
        %{
          "oneOf" => [
            %{
              "data" => %{
                "description" =>
                  "An array of resource objects representing a #{AshJsonApi.Resource.Info.type(resource)}",
                "type" => "array",
                "items" => %{
                  "$ref" => "#/definitions/#{AshJsonApi.Resource.Info.type(resource)}"
                },
                "uniqueItems" => true
              }
            },
            %{
              "$ref" => "#/definitions/errors"
            }
          ]
        }

      :delete ->
        %{
          "oneOf" => [
            nil,
            %{
              "$ref" => "#/definitions/errors"
            }
          ]
        }

      type when type in [:post_to_relationship, :patch_relationship, :delete_from_relationship] ->
        resource
        |> Ash.Resource.Info.public_relationship(route.relationship)
        |> relationship_resource_identifiers()

      _ ->
        %{
          "oneOf" => [
            %{
              "data" => %{
                "$ref" => "#/definitions/#{AshJsonApi.Resource.Info.type(resource)}"
              }
            },
            %{
              "$ref" => "#/definitions/errors"
            }
          ]
        }
    end
  end

  @doc false
  def route_href(route, api) do
    {path, path_params} =
      api
      |> AshJsonApi.Api.Info.prefix()
      |> Kernel.||("")
      |> Path.join(route.route)
      |> Path.split()
      |> Enum.reduce({[], []}, fn part, {path, path_params} ->
        case part do
          ":" <> name -> {["{#{name}}" | path], [name | path_params]}
          part -> {[part | path], path_params}
        end
      end)

    {path |> Enum.reverse() |> Path.join() |> prepend_slash(), path_params}
  end

  defp prepend_slash("/" <> _ = path), do: path
  defp prepend_slash(path), do: "/" <> path
end
