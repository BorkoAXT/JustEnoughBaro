#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using Barotrauma;

namespace JustEnoughBaro;

internal sealed class AnatomyNode
{
    public string Id { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string Type { get; init; } = string.Empty;
}

internal sealed class AnatomyJoint
{
    public string First { get; init; } = string.Empty;
    public string Second { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
}

internal sealed class CreatureAnatomy
{
    public IReadOnlyList<AnatomyNode> Nodes { get; init; } = Array.Empty<AnatomyNode>();
    public IReadOnlyList<AnatomyJoint> Joints { get; init; } = Array.Empty<AnatomyJoint>();
    public string Source { get; init; } = string.Empty;

    public static CreatureAnatomy Read(CatalogRecord record)
    {
        ContentXElement? config = ReflectionTools.FindConfigElement(record.Prefab);
        if (config is null) { return new CreatureAnatomy(); }
        try
        {
            string ragdoll = config.GetAttributeString("ragdoll", string.Empty);
            if (string.IsNullOrWhiteSpace(ragdoll))
            {
                ragdoll = config.Element.Descendants()
                    .Select(element => element.Attribute("ragdoll")?.Value ?? string.Empty)
                    .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
            }
            if (string.IsNullOrWhiteSpace(ragdoll)) { return FromDocument(config.Element, record.Source); }

            string path = ContentPath.FromRaw(config.ContentPackage, ragdoll).FullPath;
            if (!File.Exists(path)) { return FromDocument(config.Element, ragdoll); }
            XDocument document = XDocument.Load(path, LoadOptions.None);
            return FromDocument(document.Root, path);
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Could not read anatomy for {record.Identifier}: {exception.Message}");
            return new CreatureAnatomy();
        }
    }

    private static CreatureAnatomy FromDocument(XElement? root, string source)
    {
        if (root is null) { return new CreatureAnatomy { Source = source }; }
        var nodes = new List<AnatomyNode>();
        var knownIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (XElement limb in root.DescendantsAndSelf()
                     .Where(element => element.Name.LocalName.Equals("limb", StringComparison.OrdinalIgnoreCase)))
        {
            string id = limb.Attribute("id")?.Value ??
                        limb.Attribute("identifier")?.Value ??
                        nodes.Count.ToString();
            if (!knownIds.Add(id)) { continue; }
            string type = limb.Attribute("type")?.Value ?? limb.Attribute("limbtype")?.Value ?? string.Empty;
            string name = limb.Attribute("name")?.Value ??
                          (string.IsNullOrWhiteSpace(type) ? $"Limb {id}" : TextTools.Humanize(type));
            nodes.Add(new AnatomyNode { Id = id, Name = name, Type = type });
        }

        var joints = new List<AnatomyJoint>();
        foreach (XElement joint in root.DescendantsAndSelf()
                     .Where(element => element.Name.LocalName.Contains("joint", StringComparison.OrdinalIgnoreCase)))
        {
            string first = Attribute(joint, "limb1", "limb1id", "firstlimb", "parentlimb");
            string second = Attribute(joint, "limb2", "limb2id", "secondlimb", "childlimb");
            if (first.Length == 0 || second.Length == 0) { continue; }
            joints.Add(new AnatomyJoint
            {
                First = first,
                Second = second,
                Name = joint.Attribute("name")?.Value ?? joint.Name.LocalName
            });
        }

        return new CreatureAnatomy { Nodes = nodes, Joints = joints, Source = source };
    }

    private static string Attribute(XElement element, params string[] names)
    {
        foreach (string name in names)
        {
            XAttribute? attribute = element.Attributes()
                .FirstOrDefault(candidate => candidate.Name.LocalName.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (attribute is not null) { return attribute.Value; }
        }
        return string.Empty;
    }
}
