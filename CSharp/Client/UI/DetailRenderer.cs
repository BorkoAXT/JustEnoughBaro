#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Xml.Linq;
using Barotrauma;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace JustEnoughBaro;

/// <summary>
/// Builds the center detail views and the structured metadata column. The renderer keeps
/// prefab interpretation separate from window/navigation state: callers own the selected
/// record and tab, while every record link is routed through <paramref name="navigate"/>.
/// </summary>
internal sealed class DetailRenderer : IDisposable
{
    private static readonly IReadOnlyList<string> ItemTabs =
        new[] { "overview", "obtain", "usage", "connections" };
    private static readonly IReadOnlyList<string> AfflictionTabs =
        new[] { "overview", "effects", "treatments" };
    private static readonly IReadOnlyList<string> CreatureTabs =
        new[] { "overview", "preview", "skeleton", "habitat" };
    private static readonly IReadOnlyList<string> BiomeTabs =
        new[] { "overview", "map", "relations" };
    private static readonly IReadOnlyList<string> TalentTabs =
        new[] { "overview", "tree", "relations" };
    private static readonly IReadOnlyList<string> DefaultTabs =
        new[] { "overview", "relations" };

    private const int MaximumRelations = 40;
    private const int MaximumOverviewValues = 14;

    private readonly PrefabCatalog catalog;
    private readonly MetadataExtractor metadata;
    private readonly CreatureMediaRepository creatureMedia;
    private readonly CuratedKnowledgeRepository curated;
    private readonly RecipeTrackerHud tracker;
    private readonly Action<CatalogRecord> navigate;

    private readonly Dictionary<string, CreatureAnatomy> anatomyCache =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IReadOnlyList<CatalogRecord>> relationCache =
        new(StringComparer.OrdinalIgnoreCase);

    public DetailRenderer(
        PrefabCatalog catalog,
        MetadataExtractor metadata,
        CreatureMediaRepository creatureMedia,
        RecipeTrackerHud tracker,
        Action<CatalogRecord> navigate)
    {
        this.catalog = catalog ?? throw new ArgumentNullException(nameof(catalog));
        this.metadata = metadata ?? throw new ArgumentNullException(nameof(metadata));
        this.creatureMedia = creatureMedia ?? throw new ArgumentNullException(nameof(creatureMedia));
        this.tracker = tracker ?? throw new ArgumentNullException(nameof(tracker));
        this.navigate = navigate ?? throw new ArgumentNullException(nameof(navigate));
        curated = new CuratedKnowledgeRepository();
    }

    public IReadOnlyList<string> TabsFor(CatalogRecord record)
        => record.Kind switch
        {
            PrefabKind.Item => ItemTabs,
            PrefabKind.Affliction => AfflictionTabs,
            PrefabKind.Creature => CreatureTabs,
            PrefabKind.Biome => BiomeTabs,
            PrefabKind.Talent or PrefabKind.Profession => TalentTabs,
            _ => DefaultTabs
        };

    public string NormalizeTab(CatalogRecord record, string? requested)
    {
        IReadOnlyList<string> tabs = TabsFor(record);
        return tabs.FirstOrDefault(tab => tab.Equals(requested, StringComparison.OrdinalIgnoreCase))
               ?? tabs[0];
    }

    public void RenderCenter(
        GUIComponent parent,
        CatalogRecord? record,
        string? activeTab,
        Action<string> selectTab)
    {
        if (parent is null) { throw new ArgumentNullException(nameof(parent)); }
        if (selectTab is null) { throw new ArgumentNullException(nameof(selectTab)); }

        parent.ClearChildren();
        if (record is null)
        {
            Ui.Callout(
                parent.RectTransform,
                L.Get("detail.empty.title"),
                L.Get("detail.empty.body"),
                JebPalette.Cyan,
                0.22f);
            return;
        }

        string selectedTab = NormalizeTab(record, activeTab);
        var layout = new GUILayoutGroup(
            new RectTransform(Vector2.One, parent.RectTransform, Anchor.TopLeft),
            isHorizontal: false)
        {
            Stretch = true,
            AbsoluteSpacing = 5
        };

        DrawRecordHeader(layout.RectTransform, record);
        DrawTabStrip(layout.RectTransform, record, selectedTab, selectTab);

        var content = new GUIListBox(new RectTransform(new Vector2(1.0f, 0.79f), layout.RectTransform))
        {
            AutoHideScrollBar = true,
            CurrentSelectMode = GUIListBox.SelectMode.None,
            Padding = new Vector4(4, 4, 4, 8)
        };

        try
        {
            RenderTab(content, record, selectedTab);
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError(
                $"[JEB] Could not render {record.Key}/{selectedTab}: {exception.Message}");
            Ui.Callout(
                content.Content.RectTransform,
                L.Get("detail.no_data"),
                exception.Message,
                JebPalette.Red,
                0.16f);
        }
        content.UpdateScrollBarSize();
    }

    public void RenderMetadata(GUIListBox list, CatalogRecord? record)
    {
        if (list is null) { throw new ArgumentNullException(nameof(list)); }
        Ui.Reset(list);
        Ui.Separator(list.Content.RectTransform, L.Get("metadata.title"), null, JebPalette.Gold);

        if (record is null)
        {
            Ui.Callout(
                list.Content.RectTransform,
                L.Get("detail.empty.title"),
                L.Get("metadata.empty"),
                JebPalette.Cyan,
                0.16f);
            return;
        }

        Ui.Callout(
            list.Content.RectTransform,
            record.Name,
            $"{L.Get("detail.identifier")}: {record.Identifier}",
            JebPalette.Cyan,
            0.105f);

        IReadOnlyList<MetadataSection> sections;
        try
        {
            sections = metadata.Extract(record, catalog.Snapshot.Signature);
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Could not extract metadata for {record.Key}: {exception.Message}");
            Ui.Callout(list.Content.RectTransform, L.Get("detail.no_data"), exception.Message,
                JebPalette.Red, 0.15f);
            return;
        }

        if (sections.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("metadata.title"),
                L.Get("detail.no_data"), JebPalette.Muted, 0.12f);
            return;
        }

        foreach (MetadataSection section in sections)
        {
            Ui.Separator(
                list.Content.RectTransform,
                L.Get("section." + section.Key),
                null,
                SectionColor(section.Key));

            foreach (MetadataValue value in section.Values)
            {
                if (value.IsHeader)
                {
                    var heading = Ui.Heading(list.Content.RectTransform, value.Name);
                    heading.RectTransform.RelativeSize = new Vector2(1.0f, 0.05f);
                    heading.Padding = new Vector4(8 + value.Depth * 10, 4, 4, 3);
                    continue;
                }

                if (TryResolveValue(value.Value, record, out CatalogRecord? target) && target is not null)
                {
                    Ui.LinkRow(
                        list.Content.RectTransform,
                        value.Name,
                        target.Name,
                        target.Icon,
                        () => Open(target),
                        KindColor(target.Kind),
                        0.068f);
                }
                else
                {
                    DrawMetadataValue(list.Content.RectTransform, value);
                }
            }
        }
        list.UpdateScrollBarSize();
    }

    private static void DrawRecordHeader(RectTransform parent, CatalogRecord record)
    {
        var header = Ui.Frame(parent, 1.0f, 0.13f, style: "InnerFrame", color: JebPalette.Header);
        float textWidth = record.Icon is null ? 0.95f : 0.82f;
        if (record.Icon is not null)
        {
            var iconFrame = Ui.Frame(header.RectTransform, 0.12f, 0.82f, Anchor.CenterLeft,
                style: "GUIFrameListBox", color: JebPalette.PanelAlternate);
            iconFrame.RectTransform.RelativeOffset = new Vector2(0.016f, 0);
            _ = new GUIImage(
                new RectTransform(new Vector2(0.82f, 0.82f), iconFrame.RectTransform, Anchor.Center),
                record.Icon,
                scaleToFit: true)
            {
                CanBeFocused = false
            };
        }

        var title = Ui.Text(
            header.RectTransform,
            record.Name,
            JebPalette.Cream,
            GUIStyle.SubHeadingFont,
            Alignment.CenterLeft,
            wrap: true,
            width: textWidth,
            height: 0.58f,
            anchor: Anchor.TopRight);
        title.RectTransform.RelativeOffset = new Vector2(-0.02f, 0.05f);

        var subtitle = Ui.Text(
            header.RectTransform,
            $"{L.Get(record.Kind.LocalizationKey())}  •  {record.Identifier}",
            KindColor(record.Kind),
            GUIStyle.SmallFont,
            Alignment.CenterLeft,
            wrap: false,
            width: textWidth,
            height: 0.32f,
            anchor: Anchor.BottomRight);
        subtitle.RectTransform.RelativeOffset = new Vector2(-0.02f, -0.06f);
    }

    private static void DrawTabStrip(
        RectTransform parent,
        CatalogRecord record,
        string activeTab,
        Action<string> selectTab)
    {
        IReadOnlyList<string> tabs = record.Kind switch
        {
            PrefabKind.Item => ItemTabs,
            PrefabKind.Affliction => AfflictionTabs,
            PrefabKind.Creature => CreatureTabs,
            PrefabKind.Biome => BiomeTabs,
            PrefabKind.Talent or PrefabKind.Profession => TalentTabs,
            _ => DefaultTabs
        };

        var strip = new GUILayoutGroup(
            new RectTransform(new Vector2(1.0f, 0.07f), parent),
            isHorizontal: true,
            childAnchor: Anchor.CenterLeft)
        {
            Stretch = true,
            AbsoluteSpacing = 4
        };

        foreach (string tab in tabs)
        {
            string captured = tab;
            bool selected = tab.Equals(activeTab, StringComparison.OrdinalIgnoreCase);
            var button = Ui.Button(
                new RectTransform(new Vector2(1.0f / tabs.Count, 1.0f), strip.RectTransform),
                L.Get("tab." + tab),
                () =>
                {
                    selectTab(captured);
                    return true;
                },
                "GUIButtonSmall");
            button.Selected = selected;
            button.TextColor = selected ? JebPalette.Cream : JebPalette.Muted;
            button.HoverTextColor = JebPalette.Cream;
        }
    }

    private void RenderTab(GUIListBox list, CatalogRecord record, string tab)
    {
        switch (record.Kind, tab)
        {
            case (_, "overview"):
                RenderOverview(list, record);
                break;
            case (PrefabKind.Item, "obtain"):
                RenderObtain(list, record);
                break;
            case (PrefabKind.Item, "usage"):
                RenderUsage(list, record);
                break;
            case (PrefabKind.Item, "connections"):
                RenderConnections(list, record);
                break;
            case (PrefabKind.Affliction, "effects"):
                RenderAfflictionEffects(list, record);
                break;
            case (PrefabKind.Affliction, "treatments"):
                RenderTreatments(list, record);
                break;
            case (PrefabKind.Creature, "preview"):
                RenderCreaturePreview(list, record);
                break;
            case (PrefabKind.Creature, "skeleton"):
                RenderCreatureSkeleton(list, record);
                break;
            case (PrefabKind.Creature, "habitat"):
                RenderCreatureHabitat(list, record);
                break;
            case (PrefabKind.Biome, "map"):
                RenderBiomeMap(list, record);
                break;
            case (PrefabKind.Talent or PrefabKind.Profession, "tree"):
                RenderTalentTree(list, record);
                break;
            case (_, "relations"):
                RenderRelations(list, record);
                break;
            default:
                RenderOverview(list, record);
                break;
        }
    }

    private void RenderOverview(GUIListBox list, CatalogRecord record)
    {
        string description = record.Description;
        if (record.Kind == PrefabKind.Creature && string.IsNullOrWhiteSpace(description))
        {
            description = creatureMedia.Find(record.Identifier)?.Description ?? string.Empty;
        }
        if (string.IsNullOrWhiteSpace(description)) { description = L.Get("detail.no_description"); }

        Ui.Callout(
            list.Content.RectTransform,
            L.Get(record.Kind.LocalizationKey()),
            description,
            KindColor(record.Kind),
            HeightForText(description, 0.14f, 0.30f));
        Ui.KeyValue(list.Content.RectTransform, L.Get("detail.identifier"), record.Identifier,
            JebPalette.Cyan);
        if (!string.IsNullOrWhiteSpace(record.Tags))
        {
            DrawFlexibleValue(list.Content.RectTransform, L.Get("detail.tags"), record.Tags, 0);
        }
        if (!string.IsNullOrWhiteSpace(record.Source))
        {
            DrawFlexibleValue(list.Content.RectTransform, L.Get("detail.source"), record.Source, 0);
        }

        RenderCuratedOverview(list, record);

        IReadOnlyList<MetadataSection> sections = metadata.Extract(record, catalog.Snapshot.Signature);
        string[] preferred = PreferredOverviewSections(record.Kind);
        int rendered = 0;
        foreach (MetadataSection section in sections
                     .OrderBy(section => Array.IndexOf(preferred, section.Key) is int index && index >= 0
                         ? index
                         : int.MaxValue))
        {
            MetadataValue[] values = section.Values
                .Where(value => !value.IsHeader &&
                                !value.Name.Equals(L.Get("detail.name"), StringComparison.OrdinalIgnoreCase) &&
                                !value.Name.Equals(L.Get("detail.identifier"), StringComparison.OrdinalIgnoreCase) &&
                                !value.Name.Equals(L.Get("detail.description"), StringComparison.OrdinalIgnoreCase))
                .Take(MaximumOverviewValues - rendered)
                .ToArray();
            if (values.Length == 0) { continue; }
            Ui.Separator(list.Content.RectTransform, L.Get("section." + section.Key), null,
                SectionColor(section.Key));
            foreach (MetadataValue value in values)
            {
                DrawMetadataValue(list.Content.RectTransform, value);
                rendered++;
            }
            if (rendered >= MaximumOverviewValues) { break; }
        }

        IReadOnlyList<CatalogRecord> relations = RelationsFor(record).Take(5).ToArray();
        if (relations.Count > 0)
        {
            Ui.Separator(list.Content.RectTransform, L.Get("tab.relations"), null, JebPalette.Cyan);
            foreach (CatalogRecord related in relations)
            {
                DrawRecordLink(list.Content.RectTransform, related);
            }
        }
    }

    private void RenderObtain(GUIListBox list, CatalogRecord record)
    {
        IReadOnlyList<RecipeInfo> recipes = catalog.GetRecipes(record);
        Ui.Separator(list.Content.RectTransform, L.Get("section.fabrication"), null, JebPalette.Green);
        if (recipes.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.fabrication"),
                L.Get("recipe.none"), JebPalette.Muted, 0.11f);
        }
        else
        {
            for (int index = 0; index < recipes.Count; index++)
            {
                RenderRecipe(list, recipes[index], index + 1, recipes.Count);
            }
        }

        IReadOnlyList<DeconstructionSource> sources = catalog.GetSources(record);
        Ui.Separator(list.Content.RectTransform, L.Get("section.obtained_from"), null, JebPalette.Orange);
        if (sources.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.obtained_from"),
                L.Get("deconstruct.none"), JebPalette.Muted, 0.11f);
        }
        else
        {
            foreach (DeconstructionSource source in sources)
            {
                string detail = DeconstructionDetail(source.Output);
                Ui.LinkRow(
                    list.Content.RectTransform,
                    source.Source.Name,
                    detail,
                    source.Source.Icon,
                    () => Open(source.Source),
                    JebPalette.Orange,
                    0.078f);
            }
        }
    }

    private void RenderRecipe(GUIListBox list, RecipeInfo recipe, int ordinal, int recipeCount)
    {
        string heading = recipeCount > 1
            ? $"{L.Get("section.fabrication")} {ordinal}"
            : L.Get("section.fabrication");
        var summary = new List<string>();
        if (recipe.OutputAmount != 1) { summary.Add(L.F("recipe.amount", recipe.OutputAmount)); }
        if (recipe.Time > 0) { summary.Add(L.F("recipe.time", TextTools.Number(recipe.Time))); }
        if (recipe.Fabricators.Count > 0)
        {
            summary.Add(L.F("recipe.device", string.Join(", ", recipe.Fabricators)));
        }
        Ui.Callout(
            list.Content.RectTransform,
            heading,
            summary.Count > 0 ? string.Join("  •  ", summary) : recipe.OutputName,
            JebPalette.Green,
            0.11f);

        GUIButton? trackButton = null;
        trackButton = Ui.Button(
            new RectTransform(new Vector2(1.0f, 0.055f), list.Content.RectTransform),
            tracker.IsTracking(recipe) ? L.Get("action.untrack") : L.Get("action.track"),
            () =>
            {
                tracker.Toggle(recipe);
                if (trackButton is not null)
                {
                    trackButton.Text = tracker.IsTracking(recipe)
                        ? L.Get("action.untrack")
                        : L.Get("action.track");
                }
                return true;
            },
            "GUIButtonSmall");
        trackButton.TextColor = JebPalette.Cyan;

        if (recipe.RequiredMoney > 0)
        {
            Ui.KeyValue(list.Content.RectTransform, L.Get("section.requirements"),
                L.F("recipe.money", recipe.RequiredMoney), JebPalette.Gold);
        }
        if (recipe.RequiresUnlock)
        {
            Ui.KeyValue(list.Content.RectTransform, L.Get("section.requirements"),
                L.Get("recipe.unlock"), JebPalette.Orange);
        }
        if (recipe.Skills.Count > 0)
        {
            Ui.KeyValue(list.Content.RectTransform, L.Get("section.requirements"),
                string.Join(", ", recipe.Skills), JebPalette.Cream);
        }

        Ui.Separator(list.Content.RectTransform, L.Get("section.ingredients"), null, JebPalette.Green);
        foreach (RecipeIngredient ingredient in recipe.Ingredients)
        {
            DrawIngredient(list.Content.RectTransform, ingredient);
        }
    }

    private void DrawIngredient(RectTransform parent, RecipeIngredient ingredient)
    {
        string detail = IngredientDetail(ingredient);
        if (ingredient.Options.Count == 0)
        {
            string name = string.IsNullOrWhiteSpace(ingredient.Tag)
                ? L.Get("detail.no_data")
                : TextTools.Humanize(ingredient.Tag);
            Ui.KeyValue(parent, name, detail, JebPalette.Cream);
            return;
        }

        if (ingredient.Options.Count > 1)
        {
            Ui.Heading(parent, L.F("recipe.any_of", string.Join(" / ",
                ingredient.Options.Take(4).Select(option => option.Name))));
        }

        foreach (IngredientOption option in ingredient.Options.Take(16))
        {
            CatalogRecord? target = catalog.FindItem(option.Identifier);
            if (target is not null)
            {
                Ui.LinkRow(parent, option.Name, detail, target.Icon, () => Open(target),
                    JebPalette.Green, 0.072f);
            }
            else
            {
                Ui.KeyValue(parent, option.Name, detail, JebPalette.Cream);
            }
        }
    }

    private void RenderUsage(GUIListBox list, CatalogRecord record)
    {
        IReadOnlyList<RecipeUse> uses = catalog.GetUsage(record);
        Ui.Separator(list.Content.RectTransform, L.Get("section.used_in"), null, JebPalette.Cyan);
        if (uses.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.used_in"),
                L.Get("usage.none"), JebPalette.Muted, 0.11f);
        }
        else
        {
            foreach (RecipeUse use in uses)
            {
                RecipeIngredient? ingredient = use.Recipe.Ingredients.FirstOrDefault(candidate =>
                    candidate.Options.Any(option => option.Identifier.Equals(
                        record.Identifier, StringComparison.OrdinalIgnoreCase)));
                string detail = ingredient is null
                    ? L.F("recipe.amount", use.Recipe.OutputAmount)
                    : $"{L.F("recipe.amount", use.Recipe.OutputAmount)}  •  {IngredientDetail(ingredient)}";
                Ui.LinkRow(
                    list.Content.RectTransform,
                    use.Output.Name,
                    detail,
                    use.Output.Icon,
                    () => Open(use.Output),
                    JebPalette.Cyan,
                    0.078f);
            }
        }

        IReadOnlyList<DeconstructionOutput> outputs = catalog.GetDeconstruction(record);
        Ui.Separator(list.Content.RectTransform, L.Get("section.deconstruction"), null, JebPalette.Orange);
        if (outputs.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.deconstruction"),
                L.Get("deconstruct.none"), JebPalette.Muted, 0.11f);
        }
        else
        {
            foreach (DeconstructionOutput output in outputs)
            {
                CatalogRecord? target = catalog.FindItem(output.Identifier);
                string detail = DeconstructionDetail(output);
                if (target is not null)
                {
                    Ui.LinkRow(
                        list.Content.RectTransform,
                        output.Name,
                        detail,
                        target.Icon,
                        () => Open(target),
                        JebPalette.Orange,
                        0.078f);
                }
                else
                {
                    Ui.KeyValue(list.Content.RectTransform, output.Name, detail, JebPalette.Orange);
                }
                if (output.RequiredDeconstructors.Count > 0)
                {
                    Ui.KeyValue(list.Content.RectTransform, L.Get("section.requirements"),
                        string.Join(", ", output.RequiredDeconstructors), JebPalette.Muted, 1);
                }
                if (output.RequiredOtherItems.Count > 0)
                {
                    Ui.KeyValue(list.Content.RectTransform, L.Get("deconstruct.required_items"),
                        string.Join(", ", output.RequiredOtherItems), JebPalette.Muted, 1);
                }
            }
        }
    }

    private void RenderConnections(GUIListBox list, CatalogRecord record)
    {
        WiringDatabase.TryGet(record.Identifier, record.Name, out WiringPanelInfo? documented);
        IReadOnlyList<WiringPin> declared = ReadDeclaredPins(record);
        IReadOnlyList<WiringPin> pins = MergePins(declared, documented);

        Ui.Separator(list.Content.RectTransform, L.Get("section.connections"), null, JebPalette.Cyan);
        if (documented is not null && !string.IsNullOrWhiteSpace(documented.Summary))
        {
            Ui.Callout(
                list.Content.RectTransform,
                documented.Title.Length > 0 ? documented.Title : record.Name,
                documented.Summary,
                JebPalette.Cyan,
                HeightForText(documented.Summary, 0.11f, 0.20f));
        }

        if (pins.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.connections"),
                L.Get("connections.none"), JebPalette.Muted, 0.12f);
            return;
        }

        foreach (IGrouping<string, WiringPin> group in pins
                     .OrderBy(pin => DirectionOrder(pin.Direction))
                     .ThenBy(pin => pin.Name, StringComparer.CurrentCultureIgnoreCase)
                     .GroupBy(pin => NormalizedDirection(pin.Direction)))
        {
            bool output = group.Key == "output";
            Ui.Separator(
                list.Content.RectTransform,
                output ? L.Get("section.outputs") : L.Get("section.inputs"),
                null,
                output ? JebPalette.Cyan : JebPalette.Green);
            foreach (WiringPin pin in group)
            {
                string description = string.IsNullOrWhiteSpace(pin.Description)
                    ? FallbackPinDescription(pin, documented)
                    : pin.Description;
                Ui.Callout(
                    list.Content.RectTransform,
                    TextTools.Humanize(pin.Name),
                    description,
                    output ? JebPalette.Cyan : JebPalette.Green,
                    HeightForText(description, 0.105f, 0.20f));
            }
        }
    }

    private void RenderAfflictionEffects(GUIListBox list, CatalogRecord record)
    {
        int rendered = 0;
        object? descriptions = ReflectionTools.GetMember(record.Prefab, "Descriptions");
        foreach (object description in ReflectionTools.Enumerate(descriptions))
        {
            string text = TextTools.CleanDisplayText(ReflectionTools.GetMember(description, "Text"));
            if (string.IsNullOrWhiteSpace(text)) { continue; }
            string range = StrengthRange(description);
            string target = TextTools.Humanize(ReflectionTools.GetMember(description, "Target"));
            Ui.Callout(
                list.Content.RectTransform,
                string.IsNullOrWhiteSpace(target) ? range : $"{range}  •  {target}",
                text,
                JebPalette.Cyan,
                HeightForText(text, 0.12f, 0.24f));
            rendered++;
        }

        Ui.Separator(list.Content.RectTransform, L.Get("section.effects"), null, JebPalette.Orange);
        int stage = 0;
        foreach (object effect in ReflectionTools.Enumerate(
                     ReflectionTools.GetMember(record.Prefab, "Effects")))
        {
            stage++;
            string range = StrengthRange(effect);
            Ui.Callout(list.Content.RectTransform, $"{L.Get("section.effects")} {stage}",
                range, JebPalette.Orange, 0.09f);
            RenderEffectValues(list.Content.RectTransform, effect);
            rendered++;
        }

        int periodic = 0;
        foreach (object effect in ReflectionTools.Enumerate(
                     ReflectionTools.GetMember(record.Prefab, "PeriodicEffects")))
        {
            periodic++;
            string range = StrengthRange(effect);
            string min = NumberMember(effect, "MinInterval");
            string max = NumberMember(effect, "MaxInterval");
            string interval = min == max ? min : min + "–" + max;
            Ui.Callout(
                list.Content.RectTransform,
                $"{L.Get("section.effects")} P{periodic}",
                $"{range}  •  {L.F("recipe.time", interval)}",
                JebPalette.Gold,
                0.09f);
            int count = ReflectionTools.Enumerate(
                ReflectionTools.GetMember(effect, "StatusEffects")).Count();
            if (count > 0)
            {
                Ui.KeyValue(list.Content.RectTransform, L.Get("affliction.status_effects"),
                    count.ToString(CultureInfo.InvariantCulture), JebPalette.Cream, 1);
            }
            rendered++;
        }

        if (rendered == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.effects"),
                L.Get("detail.no_data"), JebPalette.Muted, 0.11f);
        }
    }

    private static void RenderEffectValues(RectTransform parent, object effect)
    {
        var fields = new (string Name, double Default)[]
        {
            ("MinVitalityDecrease", 0), ("MaxVitalityDecrease", 0),
            ("StrengthChange", 0), ("MinResistance", 0), ("MaxResistance", 0),
            ("MinSpeedMultiplier", 1), ("MaxSpeedMultiplier", 1),
            ("MinSkillMultiplier", 1), ("MaxSkillMultiplier", 1),
            ("MinScreenBlur", 0), ("MaxScreenBlur", 0),
            ("MinScreenDistort", 0), ("MaxScreenDistort", 0),
            ("ConvulseAmount", 0), ("ThermalOverlayRange", 0)
        };
        foreach ((string name, double defaultValue) in fields)
        {
            if (!TryNumber(ReflectionTools.GetMember(effect, name), out double value) ||
                Math.Abs(value - defaultValue) < 0.0005)
            {
                continue;
            }
            Ui.KeyValue(parent, TextTools.Humanize(name), TextTools.Number(value),
                value < 0 ? JebPalette.Green : JebPalette.Cream, 1);
        }

        foreach (string collectionName in new[]
                 {
                     "ResistanceFor", "ResistanceLimbs", "BlockTransformation",
                     "AfflictionStatValues", "AfflictionAbilityFlags", "StatusEffects"
                 })
        {
            object? value = ReflectionTools.GetMember(effect, collectionName);
            string rendered = TextTools.JoinValues(value, 12);
            if (!string.IsNullOrWhiteSpace(rendered))
            {
                Ui.KeyValue(parent, TextTools.Humanize(collectionName), rendered,
                    JebPalette.Cream, 1);
            }
        }
    }

    private void RenderTreatments(GUIListBox list, CatalogRecord record)
    {
        IReadOnlyList<TreatmentLink> treatments = catalog.GetTreatments(record);
        TreatmentLink[] suitable = treatments.Where(link => !link.Contraindicated).ToArray();
        TreatmentLink[] contraindicated = treatments.Where(link => link.Contraindicated).ToArray();

        Ui.Separator(list.Content.RectTransform, L.Get("section.treatments"), null, JebPalette.Green);
        if (suitable.Length == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.treatments"),
                L.Get("affliction.none_treatment"), JebPalette.Muted, 0.12f);
        }
        else
        {
            foreach (TreatmentLink link in suitable)
            {
                Ui.LinkRow(
                    list.Content.RectTransform,
                    link.Item.Name,
                    TreatmentDetail(link),
                    link.Item.Icon,
                    () => Open(link.Item),
                    JebPalette.Green,
                    0.078f);
            }
        }

        if (contraindicated.Length > 0)
        {
            Ui.Separator(list.Content.RectTransform, L.Get("section.contraindications"), null,
                JebPalette.Red);
            foreach (TreatmentLink link in contraindicated)
            {
                Ui.LinkRow(
                    list.Content.RectTransform,
                    link.Item.Name,
                    TreatmentDetail(link),
                    link.Item.Icon,
                    () => Open(link.Item),
                    JebPalette.Red,
                    0.078f);
            }
        }

        if (record.Prefab is AfflictionPrefab affliction)
        {
            CatalogRecord[] blockers = affliction.IgnoreTreatmentIfAfflictedBy
                .Select(identifier => catalog.Find(
                    PrefabKind.Affliction, TextTools.NormalizeIdentifier(identifier)))
                .Where(candidate => candidate is not null)
                .Cast<CatalogRecord>()
                .OrderBy(candidate => candidate.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray();
            if (blockers.Length > 0)
            {
                Ui.Separator(list.Content.RectTransform, L.Get("affliction.treatment_blockers"), null,
                    JebPalette.Red);
                foreach (CatalogRecord blocker in blockers)
                {
                    Ui.LinkRow(
                        list.Content.RectTransform,
                        blocker.Name,
                        L.Get("affliction.blocked_by"),
                        blocker.Icon,
                        () => Open(blocker),
                        JebPalette.Red,
                        0.078f);
                }
            }
        }

        IReadOnlyList<AfflictionCauseLink> causes = catalog.GetCauses(record);
        Ui.Separator(list.Content.RectTransform, L.Get("section.caused_by"), null, JebPalette.Orange);
        if (causes.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("section.caused_by"),
                L.Get("affliction.none_cause"), JebPalette.Muted, 0.11f);
        }
        else
        {
            foreach (AfflictionCauseLink cause in causes)
            {
                Ui.LinkRow(
                    list.Content.RectTransform,
                    cause.Source.Name,
                    L.F("affliction.strength", TextTools.Number(cause.Strength)),
                    cause.Source.Icon,
                    () => Open(cause.Source),
                    JebPalette.Orange,
                    0.078f);
            }
        }
    }

    private void RenderCreaturePreview(GUIListBox list, CatalogRecord record)
    {
        CreatureMediaRepository.Entry? entry = creatureMedia.Find(record.Identifier);
        Sprite? sprite = creatureMedia.GetSprite(record.Identifier) ?? record.Icon;
        Ui.Separator(list.Content.RectTransform, L.Get("tab.preview"), null, JebPalette.Cyan);

        if (sprite is not null)
        {
            var imageFrame = Ui.Frame(list.Content.RectTransform, 1.0f, 0.52f,
                style: "GUIFrameListBox", color: JebPalette.PanelAlternate);
            _ = new GUIImage(
                new RectTransform(new Vector2(0.95f, 0.93f), imageFrame.RectTransform, Anchor.Center),
                sprite,
                scaleToFit: true)
            {
                CanBeFocused = false
            };
        }

        string description = entry?.Description ?? record.Description;
        if (!string.IsNullOrWhiteSpace(description))
        {
            Ui.Callout(
                list.Content.RectTransform,
                entry?.Title ?? record.Name,
                description,
                JebPalette.Cyan,
                HeightForText(description, 0.14f, 0.34f));
        }
        if (entry is not null && !string.IsNullOrWhiteSpace(entry.Url))
        {
            DrawFlexibleValue(list.Content.RectTransform, L.Get("detail.source"), entry.Url, 0);
        }
        if (sprite is null && string.IsNullOrWhiteSpace(description))
        {
            Ui.Callout(list.Content.RectTransform, L.Get("tab.preview"),
                L.Get("detail.no_data"), JebPalette.Muted, 0.12f);
        }
    }

    private void RenderCreatureSkeleton(GUIListBox list, CatalogRecord record)
    {
        string key = catalog.Snapshot.Signature + ":" + record.Key;
        if (!anatomyCache.TryGetValue(key, out CreatureAnatomy? anatomy))
        {
            anatomy = CreatureAnatomy.Read(record);
            anatomyCache[key] = anatomy;
        }

        Ui.Separator(list.Content.RectTransform, L.Get("tab.skeleton"), null, JebPalette.Gold);
        if (anatomy.Nodes.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("tab.skeleton"),
                L.Get("detail.no_data"), JebPalette.Muted, 0.12f);
            return;
        }

        IReadOnlyDictionary<string, Vector2> positions = BuildAnatomyLayout(anatomy);
        var graphFrame = Ui.Frame(list.Content.RectTransform, 1.0f, 0.53f,
            style: "GUIFrameListBox", color: JebPalette.PanelAlternate);
        _ = new GUICustomComponent(
            new RectTransform(new Vector2(0.98f, 0.96f), graphFrame.RectTransform, Anchor.Center),
            onDraw: (batch, component) => DrawAnatomy(batch, component.Rect, anatomy, positions))
        {
            CanBeFocused = false,
            HideElementsOutsideFrame = true
        };

        Ui.KeyValue(list.Content.RectTransform, L.Get("creature.limbs"),
            anatomy.Nodes.Count.ToString(CultureInfo.InvariantCulture), JebPalette.Gold);
        Ui.KeyValue(list.Content.RectTransform, L.Get("creature.joints"),
            anatomy.Joints.Count.ToString(CultureInfo.InvariantCulture), JebPalette.Cyan);
        if (!string.IsNullOrWhiteSpace(anatomy.Source))
        {
            DrawFlexibleValue(list.Content.RectTransform, L.Get("detail.source"), anatomy.Source, 0);
        }

        foreach (AnatomyNode node in anatomy.Nodes.Take(48))
        {
            Ui.KeyValue(
                list.Content.RectTransform,
                node.Name,
                string.IsNullOrWhiteSpace(node.Type) ? node.Id : $"{node.Type}  •  {node.Id}",
                JebPalette.Cream,
                1);
        }
    }

    private void RenderCreatureHabitat(GUIListBox list, CatalogRecord record)
    {
        Ui.Separator(list.Content.RectTransform, L.Get("tab.habitat"), null, JebPalette.Green);
        CreatureMediaRepository.Entry? entry = creatureMedia.Find(record.Identifier);
        if (entry is not null && !string.IsNullOrWhiteSpace(entry.Description))
        {
            Ui.Callout(
                list.Content.RectTransform,
                entry.Title,
                entry.Description,
                JebPalette.Green,
                HeightForText(entry.Description, 0.14f, 0.30f));
        }

        int count = RenderSelectedMetadataSections(
            list.Content.RectTransform,
            record,
            new[] { "world", "creature" },
            28);

        CatalogRecord[] biomes = RelationsFor(record)
            .Where(related => related.Kind == PrefabKind.Biome)
            .ToArray();
        if (biomes.Length > 0)
        {
            Ui.Separator(list.Content.RectTransform, L.Get("kind.biome"), null, JebPalette.Cyan);
            foreach (CatalogRecord biome in biomes) { DrawRecordLink(list.Content.RectTransform, biome); }
        }
        else if (count == 0 && entry is null)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("tab.habitat"),
                L.Get("detail.no_data"), JebPalette.Muted, 0.12f);
        }
    }

    private void RenderBiomeMap(GUIListBox list, CatalogRecord record)
    {
        int[] zones = ReadIntegerCollection(ReflectionTools.GetMember(record.Prefab, "AllowedZones"));
        double minimum = NumberOr(ReflectionTools.GetMember(record.Prefab, "MinDifficulty"), 0);
        double maximum = NumberOr(
            ReflectionTools.GetMember(record.Prefab, "ActualMaxDifficulty", "MaxDifficulty"),
            100);

        Ui.Separator(list.Content.RectTransform, L.Get("tab.map"), null, JebPalette.Cyan);
        var mapFrame = Ui.Frame(list.Content.RectTransform, 1.0f, 0.32f,
            style: "GUIFrameListBox", color: JebPalette.PanelAlternate);
        var zoneSet = new HashSet<int>(zones);
        _ = new GUICustomComponent(
            new RectTransform(new Vector2(0.97f, 0.92f), mapFrame.RectTransform, Anchor.Center),
            onDraw: (batch, component) => DrawBiomeMap(
                batch, component.Rect, zoneSet, minimum, maximum))
        {
            CanBeFocused = false,
            HideElementsOutsideFrame = true
        };

        if (zones.Length > 0)
        {
            Ui.KeyValue(list.Content.RectTransform, L.Get("biome.allowed_zones"),
                string.Join(", ", zones), JebPalette.Cyan);
        }
        Ui.KeyValue(list.Content.RectTransform, L.Get("biome.difficulty"),
            $"{TextTools.Number(minimum)}–{TextTools.Number(maximum)}", JebPalette.Gold);
        RenderSelectedMetadataSections(list.Content.RectTransform, record,
            new[] { "world" }, 32);
    }

    private void RenderTalentTree(GUIListBox list, CatalogRecord record)
    {
        Ui.Separator(list.Content.RectTransform, L.Get("tab.tree"), null, JebPalette.Gold);
        int metadataCount = RenderSelectedMetadataSections(
            list.Content.RectTransform,
            record,
            new[] { "talent" },
            36);
        CatalogRecord[] related = RelationsFor(record)
            .Where(candidate => candidate.Kind is PrefabKind.Talent or PrefabKind.Profession)
            .ToArray();
        if (related.Length > 0)
        {
            Ui.Separator(list.Content.RectTransform, L.Get("tab.relations"), null, JebPalette.Cyan);
            foreach (CatalogRecord candidate in related)
            {
                DrawRecordLink(list.Content.RectTransform, candidate);
            }
        }
        else if (metadataCount == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("tab.tree"),
                L.Get("detail.no_data"), JebPalette.Muted, 0.12f);
        }
    }

    private void RenderCuratedOverview(GUIListBox list, CatalogRecord record)
    {
        if (curated.TryGetProfession(record, out CuratedKnowledgeRepository.ProfessionKnowledge profession))
        {
            if (profession.Responsibilities.Count > 0)
            {
                Ui.Separator(list.Content.RectTransform, L.Get("section.responsibilities"), null,
                    JebPalette.Gold);
                foreach (string responsibility in profession.Responsibilities)
                {
                    Ui.Callout(list.Content.RectTransform, L.Get("section.responsibilities"),
                        responsibility, JebPalette.Gold,
                        HeightForText(responsibility, 0.10f, 0.18f));
                }
            }
            if (profession.Tips.Count > 0)
            {
                Ui.Separator(list.Content.RectTransform, L.Get("section.tips"), null, JebPalette.Cyan);
                foreach (string tip in profession.Tips)
                {
                    Ui.Callout(list.Content.RectTransform, L.Get("section.tip"), tip,
                        JebPalette.Cyan, HeightForText(tip, 0.10f, 0.20f));
                }
            }
            if (!string.IsNullOrWhiteSpace(profession.Source))
            {
                DrawFlexibleValue(list.Content.RectTransform, L.Get("detail.source"),
                    profession.Source, 0);
            }
        }

        if (curated.TryGetSubmarine(record, out CuratedKnowledgeRepository.SubmarineKnowledge submarine))
        {
            Ui.Separator(list.Content.RectTransform, L.Get("section.vessel_specs"), null,
                JebPalette.Cyan);
            Ui.KeyValue(list.Content.RectTransform, L.Get("submarine.horizontal_speed"),
                TextTools.Number(submarine.HorizontalSpeed), JebPalette.Cyan);
            Ui.KeyValue(list.Content.RectTransform, L.Get("submarine.descent_speed"),
                TextTools.Number(submarine.DescentSpeed), JebPalette.Cyan);
            if (submarine.Weapons.Count > 0)
            {
                Ui.KeyValue(list.Content.RectTransform, L.Get("submarine.armament"),
                    string.Join(", ", submarine.Weapons), JebPalette.Red);
            }
            if (submarine.Hardpoints > 0)
            {
                Ui.KeyValue(list.Content.RectTransform, L.Get("submarine.hardpoints"),
                    submarine.Hardpoints.ToString(CultureInfo.InvariantCulture), JebPalette.Gold);
            }
            if (submarine.LargeHardpoints > 0)
            {
                Ui.KeyValue(list.Content.RectTransform, L.Get("submarine.large_hardpoints"),
                    submarine.LargeHardpoints.ToString(CultureInfo.InvariantCulture), JebPalette.Gold);
            }
            if (submarine.Other.Count > 0)
            {
                Ui.KeyValue(list.Content.RectTransform, L.Get("section.other"),
                    string.Join(", ", submarine.Other), JebPalette.Cream);
            }
            if (!string.IsNullOrWhiteSpace(submarine.Source))
            {
                DrawFlexibleValue(list.Content.RectTransform, L.Get("detail.source"),
                    submarine.Source, 0);
            }
        }
    }

    private void RenderRelations(GUIListBox list, CatalogRecord record)
    {
        Ui.Separator(list.Content.RectTransform, L.Get("tab.relations"), null, JebPalette.Cyan);
        IReadOnlyList<CatalogRecord> related = RelationsFor(record);
        if (related.Count == 0)
        {
            Ui.Callout(list.Content.RectTransform, L.Get("tab.relations"),
                L.Get("detail.no_data"), JebPalette.Muted, 0.12f);
            return;
        }

        foreach (IGrouping<PrefabKind, CatalogRecord> group in related.GroupBy(item => item.Kind))
        {
            Ui.Separator(list.Content.RectTransform, L.Get(group.Key.LocalizationKey()), null,
                KindColor(group.Key));
            foreach (CatalogRecord target in group) { DrawRecordLink(list.Content.RectTransform, target); }
        }
    }

    private int RenderSelectedMetadataSections(
        RectTransform parent,
        CatalogRecord record,
        IReadOnlyCollection<string> selectedSections,
        int maximum)
    {
        IReadOnlyList<MetadataSection> sections = metadata.Extract(record, catalog.Snapshot.Signature);
        int count = 0;
        foreach (MetadataSection section in sections.Where(section => selectedSections.Contains(section.Key)))
        {
            MetadataValue[] values = section.Values.Take(maximum - count).ToArray();
            if (values.Length == 0) { continue; }
            Ui.Separator(parent, L.Get("section." + section.Key), null, SectionColor(section.Key));
            foreach (MetadataValue value in values)
            {
                if (value.IsHeader)
                {
                    Ui.Heading(parent, value.Name);
                }
                else
                {
                    DrawMetadataValue(parent, value);
                }
                count++;
            }
            if (count >= maximum) { break; }
        }
        return count;
    }

    private IReadOnlyList<CatalogRecord> RelationsFor(CatalogRecord record)
    {
        string cacheKey = catalog.Snapshot.Signature + ":" + record.Key;
        if (relationCache.TryGetValue(cacheKey, out IReadOnlyList<CatalogRecord>? cached))
        {
            return cached;
        }

        var related = new Dictionary<string, CatalogRecord>(StringComparer.OrdinalIgnoreCase);
        var identifiers = catalog.Snapshot.All
            .GroupBy(item => item.Identifier, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                group => group.Key,
                group => (IReadOnlyList<CatalogRecord>)group.ToArray(),
                StringComparer.OrdinalIgnoreCase);

        void AddIdentifier(string? raw)
        {
            foreach (string candidate in IdentifierCandidates(raw))
            {
                if (!identifiers.TryGetValue(candidate, out IReadOnlyList<CatalogRecord>? matches))
                {
                    continue;
                }
                foreach (CatalogRecord match in matches)
                {
                    if (match.Key != record.Key) { related.TryAdd(match.Key, match); }
                }
            }
        }

        ContentXElement? config = ReflectionTools.FindConfigElement(record.Prefab);
        if (config is not null)
        {
            try
            {
                foreach (XAttribute attribute in config.Element.DescendantsAndSelf().Attributes())
                {
                    AddIdentifier(attribute.Value);
                    if (related.Count >= MaximumRelations) { break; }
                }
            }
            catch { }
        }

        foreach (string member in new[]
                 {
                     "VariantOf", "ParentPrefab", "Parent", "Biome", "BiomeIdentifier",
                     "Job", "JobIdentifier", "Talent", "Talents", "RequiredTalents",
                     "Unlocks", "LocationType", "Faction", "MissionType"
                 })
        {
            object? value = ReflectionTools.GetMember(record.Prefab, member);
            if (value is IEnumerable enumerable and not string)
            {
                foreach (object entry in ReflectionTools.Enumerate(enumerable))
                {
                    AddIdentifier(TextTools.Stringify(
                        ReflectionTools.GetMember(entry, "Identifier", "Value", "Name") ?? entry));
                }
            }
            else
            {
                AddIdentifier(TextTools.Stringify(
                    ReflectionTools.GetMember(value, "Identifier", "Value", "Name") ?? value));
            }
        }

        // Include reverse references. This runs only when a relation-bearing view is opened and
        // is cached per content signature; it never mutates or instantiates game prefabs.
        if (related.Count < MaximumRelations)
        {
            foreach (CatalogRecord candidate in catalog.Snapshot.All)
            {
                if (candidate.Key == record.Key || related.ContainsKey(candidate.Key)) { continue; }
                if (!ReferencesIdentifier(candidate, record.Identifier)) { continue; }
                related[candidate.Key] = candidate;
                if (related.Count >= MaximumRelations) { break; }
            }
        }

        CatalogRecord[] result = related.Values
            .OrderBy(item => item.Kind)
            .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
        relationCache[cacheKey] = result;
        return result;
    }

    private static bool ReferencesIdentifier(CatalogRecord candidate, string identifier)
    {
        ContentXElement? config = ReflectionTools.FindConfigElement(candidate.Prefab);
        if (config is null) { return false; }
        try
        {
            foreach (XAttribute attribute in config.Element.DescendantsAndSelf().Attributes())
            {
                if (IdentifierCandidates(attribute.Value).Any(value =>
                        value.Equals(identifier, StringComparison.OrdinalIgnoreCase)))
                {
                    return true;
                }
            }
        }
        catch { }
        return false;
    }

    private static IEnumerable<string> IdentifierCandidates(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) { yield break; }
        string whole = TextTools.NormalizeIdentifier(raw);
        if (whole.Length > 0) { yield return whole; }
        foreach (string part in raw.Split(
                     new[] { ',', ';', '|', '+', ' ', '\t', '\r', '\n' },
                     StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            string candidate = TextTools.NormalizeIdentifier(part);
            if (candidate.Length > 0 && !candidate.Equals(whole, StringComparison.OrdinalIgnoreCase))
            {
                yield return candidate;
            }
        }
    }

    private static IReadOnlyList<WiringPin> ReadDeclaredPins(CatalogRecord record)
    {
        ContentXElement? config = ReflectionTools.FindConfigElement(record.Prefab);
        if (config is null) { return Array.Empty<WiringPin>(); }
        var pins = new List<WiringPin>();
        try
        {
            foreach (XElement panel in config.Element.DescendantsAndSelf().Where(element =>
                         element.Name.LocalName.Equals("connectionpanel", StringComparison.OrdinalIgnoreCase)))
            {
                foreach (XElement element in panel.Elements())
                {
                    string direction = element.Name.LocalName.ToLowerInvariant();
                    if (direction is not ("input" or "output")) { continue; }
                    string name = element.Attribute("name")?.Value ?? direction;
                    string description = element.Attribute("description")?.Value ??
                                         element.Attribute("tooltip")?.Value ?? string.Empty;
                    pins.Add(new WiringPin
                    {
                        Name = name,
                        Direction = direction,
                        Description = description
                    });
                }
            }
        }
        catch { }
        return pins;
    }

    private static IReadOnlyList<WiringPin> MergePins(
        IReadOnlyList<WiringPin> declared,
        WiringPanelInfo? documented)
    {
        if (declared.Count == 0) { return documented?.Pins ?? Array.Empty<WiringPin>(); }
        // The loaded prefab is authoritative. Wiki panels can document a shared
        // family with more connections than a particular variant (for example,
        // wrecked lights and doors), so enrich declared pins without inventing
        // additional connections that the selected prefab does not expose.
        var result = new List<WiringPin>(declared.Count);
        foreach (WiringPin pin in declared)
        {
            WiringPin? wiki = documented is null
                ? null
                : WiringDatabase.MatchPin(documented, pin.Name, pin.Direction);
            result.Add(new WiringPin
            {
                Name = pin.Name,
                Direction = pin.Direction,
                Description = !string.IsNullOrWhiteSpace(wiki?.Description)
                    ? wiki.Description
                    : pin.Description
            });
        }
        return result;
    }

    private static string FallbackPinDescription(WiringPin pin, WiringPanelInfo? panel)
    {
        string key = WiringDatabase.NormalizeKey(pin.Name);
        bool output = NormalizedDirection(pin.Direction) == "output";
        string language = L.CurrentLanguage;
        if (key.Contains("powervalue", StringComparison.Ordinal))
        {
            return L.Get("connections.pin.signal_output");
        }
        if (key.Contains("power", StringComparison.Ordinal))
        {
            return language switch
            {
                "ru" => output ? "Передаёт электрическую мощность подключённым устройствам." : "Получает электрическую мощность от подключённой сети.",
                "pt" => output ? "Fornece energia elétrica aos dispositivos conectados." : "Recebe energia elétrica da rede conectada.",
                _ => output ? "Supplies electrical power to connected devices." : "Receives electrical power from the connected grid."
            };
        }
        if (key.Contains("shutdown", StringComparison.Ordinal))
        {
            return L.Get("connections.pin.shutdown");
        }
        if (key.Contains("containedconditions", StringComparison.Ordinal))
        {
            return L.Get("connections.pin.contained_conditions");
        }
        if (key.Contains("containeditems", StringComparison.Ordinal) ||
            key.Contains("ammunition", StringComparison.Ordinal))
        {
            return L.Get("connections.pin.contained_items");
        }
        if (key.Contains("condition", StringComparison.Ordinal))
        {
            return L.Get("connections.pin.condition");
        }
        if (output && key.Contains("state", StringComparison.Ordinal))
        {
            return L.Get("connections.pin.state");
        }
        if (!output && key.Contains("position", StringComparison.Ordinal))
        {
            return L.Get("connections.pin.position_input");
        }
        if (key.Contains("trigger", StringComparison.Ordinal) ||
            key.Contains("activate", StringComparison.Ordinal))
        {
            return L.Get(output
                ? "connections.pin.trigger_output"
                : "connections.pin.trigger_input");
        }
        if (key.Contains("toggle", StringComparison.Ordinal))
        {
            return language switch
            {
                "ru" => "Переключает указанное состояние при получении ненулевого сигнала.",
                "pt" => "Alterna o estado indicado ao receber um sinal diferente de zero.",
                _ => "Toggles the indicated state when a non-zero signal is received."
            };
        }
        if (key.StartsWith("set", StringComparison.Ordinal))
        {
            return language switch
            {
                "ru" => "Устанавливает указанное состояние или значение из входного сигнала.",
                "pt" => "Define o estado ou valor indicado a partir do sinal de entrada.",
                _ => "Sets the indicated state or value from the input signal."
            };
        }
        if (key.Contains("signal", StringComparison.Ordinal))
        {
            return L.Get(output
                ? "connections.pin.signal_output"
                : "connections.pin.signal_input");
        }
        if (!string.IsNullOrWhiteSpace(panel?.Summary))
        {
            return panel.Summary + " " + L.Get(output
                ? "connections.output_summary"
                : "connections.input_summary");
        }
        return L.Get(output
            ? "connections.pin.signal_output"
            : "connections.pin.signal_input");
    }

    private static string NormalizedDirection(string? direction)
        => direction?.Contains("out", StringComparison.OrdinalIgnoreCase) == true
            ? "output"
            : "input";

    private static int DirectionOrder(string? direction)
        => NormalizedDirection(direction) == "input" ? 0 : 1;

    private static IReadOnlyDictionary<string, Vector2> BuildAnatomyLayout(CreatureAnatomy anatomy)
    {
        var nodes = anatomy.Nodes.ToDictionary(node => node.Id, StringComparer.OrdinalIgnoreCase);
        var adjacency = nodes.Keys.ToDictionary(
            id => id,
            _ => new HashSet<string>(StringComparer.OrdinalIgnoreCase),
            StringComparer.OrdinalIgnoreCase);
        foreach (AnatomyJoint joint in anatomy.Joints)
        {
            if (!adjacency.ContainsKey(joint.First) || !adjacency.ContainsKey(joint.Second)) { continue; }
            adjacency[joint.First].Add(joint.Second);
            adjacency[joint.Second].Add(joint.First);
        }

        string root = adjacency
            .OrderByDescending(pair => pair.Value.Count)
            .ThenBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
            .Select(pair => pair.Key)
            .First();
        var levels = new Dictionary<int, List<string>>();
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { root };
        var queue = new Queue<(string Id, int Level)>();
        queue.Enqueue((root, 0));
        int deepest = 0;
        while (queue.Count > 0)
        {
            (string id, int level) = queue.Dequeue();
            deepest = Math.Max(deepest, level);
            if (!levels.TryGetValue(level, out List<string>? row))
            {
                row = new List<string>();
                levels[level] = row;
            }
            row.Add(id);
            foreach (string next in adjacency[id].OrderBy(value => value, StringComparer.OrdinalIgnoreCase))
            {
                if (visited.Add(next)) { queue.Enqueue((next, level + 1)); }
            }
        }
        foreach (string id in nodes.Keys.Where(id => !visited.Contains(id)))
        {
            if (!levels.TryGetValue(deepest + 1, out List<string>? row))
            {
                row = new List<string>();
                levels[deepest + 1] = row;
            }
            row.Add(id);
        }

        var positions = new Dictionary<string, Vector2>(StringComparer.OrdinalIgnoreCase);
        int levelCount = Math.Max(1, levels.Count);
        foreach ((int level, List<string> row) in levels.OrderBy(pair => pair.Key))
        {
            for (int index = 0; index < row.Count; index++)
            {
                positions[row[index]] = new Vector2(
                    (index + 1.0f) / (row.Count + 1.0f),
                    (level + 1.0f) / (levelCount + 1.0f));
            }
        }
        return positions;
    }

    private static void DrawAnatomy(
        SpriteBatch batch,
        Rectangle rect,
        CreatureAnatomy anatomy,
        IReadOnlyDictionary<string, Vector2> positions)
    {
        GUI.DrawFilledRectangle(batch, rect.Location.ToVector2(), rect.Size.ToVector2(),
            JebPalette.PanelAlternate);
        const float padding = 24.0f;
        Vector2 PointFor(string id)
        {
            if (!positions.TryGetValue(id, out Vector2 normalized)) { return rect.Center.ToVector2(); }
            return new Vector2(
                rect.Left + padding + normalized.X * Math.Max(1, rect.Width - padding * 2),
                rect.Top + padding + normalized.Y * Math.Max(1, rect.Height - padding * 2));
        }

        foreach (AnatomyJoint joint in anatomy.Joints)
        {
            if (!positions.ContainsKey(joint.First) || !positions.ContainsKey(joint.Second)) { continue; }
            GUI.DrawLine(batch, PointFor(joint.First), PointFor(joint.Second),
                JebPalette.Cyan * 0.7f, width: 2.0f);
        }
        bool labels = anatomy.Nodes.Count <= 20;
        foreach (AnatomyNode node in anatomy.Nodes)
        {
            Vector2 point = PointFor(node.Id);
            GUI.DrawFilledRectangle(batch, point - new Vector2(5), new Vector2(10), JebPalette.Gold);
            GUI.DrawRectangle(batch, point - new Vector2(6), new Vector2(12), JebPalette.Cream);
            if (labels)
            {
                string label = node.Name.Length > 18 ? node.Name[..17] + "…" : node.Name;
                GUIStyle.SmallFont.DrawString(batch, label, point + new Vector2(8, -7), JebPalette.Text);
            }
        }
    }

    private static void DrawBiomeMap(
        SpriteBatch batch,
        Rectangle rect,
        ISet<int> allowedZones,
        double minimumDifficulty,
        double maximumDifficulty)
    {
        GUI.DrawFilledRectangle(batch, rect.Location.ToVector2(), rect.Size.ToVector2(),
            JebPalette.PanelAlternate);
        int zones = Math.Max(5, allowedZones.Count == 0 ? 5 : allowedZones.Max());
        float inset = 12.0f;
        float bandTop = rect.Top + inset;
        float bandHeight = Math.Max(30.0f, rect.Height - 58.0f);
        float bandWidth = Math.Max(1.0f, (rect.Width - inset * 2) / zones);
        for (int zone = 1; zone <= zones; zone++)
        {
            var zoneRect = new Rectangle(
                (int)(rect.Left + inset + (zone - 1) * bandWidth),
                (int)bandTop,
                Math.Max(1, (int)bandWidth - 2),
                (int)bandHeight);
            bool allowed = allowedZones.Count == 0 || allowedZones.Contains(zone);
            Color fill = allowed
                ? Color.Lerp(JebPalette.Green, JebPalette.Cyan, zone / (float)zones) * 0.42f
                : JebPalette.Row * 0.38f;
            GUI.DrawFilledRectangle(batch, zoneRect.Location.ToVector2(), zoneRect.Size.ToVector2(), fill);
            GUI.DrawRectangle(batch, zoneRect, allowed ? JebPalette.Cyan * 0.7f : JebPalette.Divider);
            GUIStyle.SmallFont.DrawString(batch, zone.ToString(CultureInfo.InvariantCulture),
                new Vector2(zoneRect.Center.X - 4, zoneRect.Top + 5),
                allowed ? JebPalette.Cream : JebPalette.Muted);
        }

        float left = rect.Left + inset;
        float width = Math.Max(1, rect.Width - inset * 2);
        float y = rect.Bottom - 25;
        GUI.DrawLine(batch, new Vector2(left, y), new Vector2(left + width, y), JebPalette.Divider,
            width: 5.0f);
        float minimum = MathHelper.Clamp((float)minimumDifficulty / 100.0f, 0, 1);
        float maximum = MathHelper.Clamp((float)maximumDifficulty / 100.0f, minimum, 1);
        GUI.DrawLine(batch, new Vector2(left + width * minimum, y),
            new Vector2(left + width * maximum, y), JebPalette.Gold, width: 7.0f);
    }

    private void DrawRecordLink(RectTransform parent, CatalogRecord record)
    {
        Ui.LinkRow(
            parent,
            record.Name,
            $"{L.Get(record.Kind.LocalizationKey())}  •  {record.Identifier}",
            record.Icon,
            () => Open(record),
            KindColor(record.Kind),
            0.078f);
    }

    private bool TryResolveValue(string value, CatalogRecord current, out CatalogRecord? record)
    {
        record = null;
        string identifier = TextTools.NormalizeIdentifier(value);
        if (identifier.Length == 0) { return false; }
        record = catalog.Snapshot.All.FirstOrDefault(candidate =>
            candidate.Key != current.Key &&
            candidate.Identifier.Equals(identifier, StringComparison.OrdinalIgnoreCase));
        return record is not null;
    }

    private bool Open(CatalogRecord record)
    {
        navigate(record);
        return true;
    }

    private static void DrawMetadataValue(RectTransform parent, MetadataValue value)
        => DrawFlexibleValue(parent, value.Name, value.Value, value.Depth);

    private static void DrawFlexibleValue(RectTransform parent, string name, string value, int depth)
    {
        if (value.Length > 150 || value.Count(character => character == '\n') > 1)
        {
            Ui.Callout(parent, name, value, JebPalette.Cyan,
                HeightForText(value, 0.12f, 0.28f));
        }
        else
        {
            Ui.KeyValue(parent, name, value, JebPalette.Text, depth);
        }
    }

    private static float HeightForText(string? value, float minimum, float maximum)
    {
        int length = value?.Length ?? 0;
        int lines = value?.Count(character => character == '\n') ?? 0;
        float estimated = minimum + Math.Min(0.18f, length / 900.0f) + Math.Min(0.08f, lines * 0.018f);
        return Math.Clamp(estimated, minimum, maximum);
    }

    private static string IngredientDetail(RecipeIngredient ingredient)
    {
        var values = new List<string> { L.F("recipe.amount", ingredient.Amount) };
        if (ingredient.MinimumCondition > 0 || ingredient.MaximumCondition < 1)
        {
            values.Add(L.F(
                "recipe.condition",
                TextTools.Number(ingredient.MinimumCondition * 100),
                TextTools.Number(ingredient.MaximumCondition * 100)));
        }
        if (ingredient.ConsumesCondition)
        {
            values.Add(L.Get("recipe.consumes_condition"));
        }
        return string.Join("  •  ", values);
    }

    private static string AmountProbability(int amount, float probability)
    {
        string result = L.F("recipe.amount", amount);
        if (probability < 0.999f)
        {
            result += "  •  " + TextTools.Number(probability * 100) + "%";
        }
        return result;
    }

    private static string DeconstructionDetail(DeconstructionOutput output)
    {
        var parts = new List<string> { AmountProbability(output.Amount, output.Probability) };
        if (output.MinimumCondition > 0.0005f || output.MaximumCondition < 0.9995f)
        {
            parts.Add(L.F(
                "deconstruct.source_condition",
                TextTools.Number(output.MinimumCondition * 100),
                TextTools.Number(output.MaximumCondition * 100)));
        }
        if (output.OutputConditionMinimum < 0.9995f || output.OutputConditionMaximum < 0.9995f)
        {
            parts.Add(L.F(
                "deconstruct.output_condition",
                TextTools.Number(output.OutputConditionMinimum * 100),
                TextTools.Number(output.OutputConditionMaximum * 100)));
        }
        return string.Join("  •  ", parts);
    }

    private static string TreatmentDetail(TreatmentLink link)
    {
        var parts = new List<string>();
        if (Math.Abs(link.Suitability) > 0.0005f)
        {
            parts.Add(L.F("affliction.suitability", TextTools.Number(link.Suitability)));
        }
        if (Math.Abs(link.Strength) > 0.0005f)
        {
            parts.Add(L.F("affliction.strength", TextTools.Number(link.Strength)));
        }
        if (!string.IsNullOrWhiteSpace(link.Note)) { parts.Add(link.Note); }
        return parts.Count == 0 ? L.Get("section.treatments") : string.Join("  •  ", parts);
    }

    private static string StrengthRange(object value)
    {
        string minimum = NumberMember(value, "MinStrength");
        string maximum = NumberMember(value, "MaxStrength");
        return L.F("affliction.strength", minimum + "–" + maximum);
    }

    private static string NumberMember(object value, string member)
        => TryNumber(ReflectionTools.GetMember(value, member), out double number)
            ? TextTools.Number(number)
            : "0";

    private static double NumberOr(object? value, double fallback)
        => TryNumber(value, out double number) ? number : fallback;

    private static bool TryNumber(object? value, out double result)
    {
        try
        {
            if (value is null)
            {
                result = 0;
                return false;
            }
            result = Convert.ToDouble(value, CultureInfo.InvariantCulture);
            return !double.IsNaN(result) && !double.IsInfinity(result);
        }
        catch
        {
            result = 0;
            return false;
        }
    }

    private static int[] ReadIntegerCollection(object? value)
    {
        var values = new List<int>();
        foreach (object entry in ReflectionTools.Enumerate(value))
        {
            try { values.Add(Convert.ToInt32(entry, CultureInfo.InvariantCulture)); }
            catch { }
        }
        return values.Distinct().OrderBy(number => number).ToArray();
    }

    private static string[] PreferredOverviewSections(PrefabKind kind)
        => kind switch
        {
            PrefabKind.Item => new[] { "gameplay", "weapon", "medical", "electrical", "contained" },
            PrefabKind.Affliction => new[] { "medical", "gameplay" },
            PrefabKind.Creature => new[] { "creature", "gameplay", "world" },
            PrefabKind.Biome => new[] { "world", "gameplay" },
            PrefabKind.Talent or PrefabKind.Profession => new[] { "talent", "gameplay" },
            PrefabKind.Mission => new[] { "mission", "world", "gameplay" },
            _ => new[] { "gameplay", "world", "other" }
        };

    private static Color KindColor(PrefabKind kind)
        => kind switch
        {
            PrefabKind.Item => JebPalette.Green,
            PrefabKind.Affliction => JebPalette.Red,
            PrefabKind.Creature => JebPalette.Orange,
            PrefabKind.Biome => JebPalette.Cyan,
            PrefabKind.Talent or PrefabKind.Profession => JebPalette.Gold,
            _ => JebPalette.Cream
        };

    private static Color SectionColor(string section)
        => section.ToLowerInvariant() switch
        {
            "weapon" => JebPalette.Red,
            "medical" => JebPalette.Green,
            "electrical" => JebPalette.Cyan,
            "creature" => JebPalette.Orange,
            "world" => JebPalette.Cyan,
            "talent" => JebPalette.Gold,
            "mission" => JebPalette.Orange,
            "contained" => JebPalette.Cream,
            "visual" => JebPalette.Cyan,
            _ => JebPalette.Gold
        };

    public void Dispose()
    {
        anatomyCache.Clear();
        relationCache.Clear();
    }
}
