#nullable enable

using System;
using System.Collections.Generic;
using System.Linq;
using Barotrauma;
using Microsoft.Xna.Framework;

namespace JustEnoughBaro;

internal sealed class RecipeTrackerHud : IDisposable
{
    private const int DrawOrder = 920;
    private readonly JebConfig config;
    private readonly UserState state;
    private readonly Action saveState;

    private GUIFrame? frame;
    private GUIListBox? list;
    private GUIDragHandle? dragHandle;
    private string lastCountSignature = string.Empty;
    private double refreshTimer;
    private bool wasDragging;

    public RecipeTrackerHud(JebConfig config, UserState state, Action saveState)
    {
        this.config = config;
        this.state = state;
        this.saveState = saveState;
    }

    public bool IsTracking(RecipeInfo recipe)
        => state.TrackedRecipe?.RecipeId.Equals(recipe.Id, StringComparison.OrdinalIgnoreCase) == true;

    public void Toggle(RecipeInfo recipe)
    {
        if (IsTracking(recipe))
        {
            state.TrackedRecipe = null;
        }
        else
        {
            state.TrackedRecipe = new TrackedRecipe
            {
                RecipeId = recipe.Id,
                OutputIdentifier = recipe.OutputIdentifier,
                OutputName = recipe.OutputName,
                Ingredients = recipe.Ingredients.Select(ingredient => new TrackedIngredient
                {
                    Key = ingredient.TrackerKey,
                    Name = IngredientName(ingredient),
                    Required = ingredient.Amount,
                    AcceptedIdentifiers = ingredient.Options
                        .Select(option => option.Identifier)
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToList()
                }).ToList()
            };
        }
        lastCountSignature = string.Empty;
        saveState();
        Rebuild();
    }

    public void Clear()
    {
        state.TrackedRecipe = null;
        saveState();
        DisposeFrame();
    }

    public void Update(double deltaTime)
    {
        if (!config.ShowHudTracker || state.TrackedRecipe is null)
        {
            DisposeFrame();
            return;
        }

        refreshTimer -= deltaTime;
        if (refreshTimer <= 0)
        {
            refreshTimer = 0.25;
            string signature = CountSignature(state.TrackedRecipe);
            if (!signature.Equals(lastCountSignature, StringComparison.Ordinal))
            {
                lastCountSignature = signature;
                Rebuild();
            }
        }

        frame?.AddToGUIUpdateList(order: DrawOrder);
        bool dragging = dragHandle?.Dragging == true;
        if (wasDragging && !dragging && frame is not null)
        {
            int roomX = Math.Max(1, GUI.UIWidth - frame.Rect.Width);
            int roomY = Math.Max(1, GameMain.GraphicsHeight - frame.Rect.Height);
            config.TrackerX = Math.Clamp(frame.Rect.X / (float)roomX, 0.0f, 1.0f);
            config.TrackerY = Math.Clamp(frame.Rect.Y / (float)roomY, 0.0f, 1.0f);
            saveState();
        }
        wasDragging = dragging;
    }

    private void Rebuild()
    {
        TrackedRecipe? tracked = state.TrackedRecipe;
        if (tracked is null)
        {
            DisposeFrame();
            return;
        }
        EnsureFrame();
        if (list is null) { return; }

        Ui.Reset(list);
        Ui.Separator(list.Content.RectTransform, tracked.OutputName, null, JebPalette.Cyan);
        IReadOnlyDictionary<string, int> counts = InventoryCounts();
        foreach (TrackedIngredient ingredient in tracked.Ingredients)
        {
            int carried = ingredient.AcceptedIdentifiers.Sum(
                identifier => counts.TryGetValue(identifier, out int count) ? count : 0);
            int shown = Math.Min(carried, ingredient.Required);
            bool complete = carried >= ingredient.Required;
            var row = Ui.KeyValue(
                list.Content.RectTransform,
                ingredient.Name,
                L.F("tracker.progress", shown, ingredient.Required),
                complete ? JebPalette.Green : JebPalette.Cream);
            if (complete) { row.ToolTip = L.Get("tracker.complete"); }
        }
        list.UpdateScrollBarSize();
    }

    private void EnsureFrame()
    {
        if (frame is not null) { return; }
        frame = new GUIFrame(
            new RectTransform(new Vector2(0.235f, 0.24f), GUI.Canvas, Anchor.TopLeft, Pivot.TopLeft),
            "GUIFrameListBox")
        {
            Color = JebPalette.Panel
        };
        int roomX = Math.Max(0, GUI.UIWidth - frame.Rect.Width);
        int roomY = Math.Max(0, GameMain.GraphicsHeight - frame.Rect.Height);
        frame.RectTransform.ScreenSpaceOffset = new Point(
            (int)(roomX * Math.Clamp(config.TrackerX, 0.0f, 1.0f)),
            (int)(roomY * Math.Clamp(config.TrackerY, 0.0f, 1.0f)));

        var header = Ui.Frame(frame.RectTransform, 0.95f, 0.21f, Anchor.TopCenter,
            "InnerFrame", JebPalette.Header);
        Ui.Text(header.RectTransform, L.Get("tracker.title"), JebPalette.Gold,
            GUIStyle.SmallFont, Alignment.CenterLeft, false, 0.74f, 1.0f, Anchor.CenterLeft)
            .RectTransform.RelativeOffset = new Vector2(0.04f, 0);
        Ui.Button(
            Ui.Relative(header.RectTransform, 0.18f, 0.72f, Anchor.CenterRight),
            "×",
            () =>
            {
                Clear();
                return true;
            },
            "GUICancelButton");

        dragHandle = new GUIDragHandle(
            new RectTransform(new Vector2(0.76f, 1.0f), header.RectTransform, Anchor.CenterLeft),
            frame.RectTransform,
            style: string.Empty)
        {
            CanBeFocused = true
        };

        list = new GUIListBox(
            new RectTransform(new Vector2(0.94f, 0.72f), frame.RectTransform, Anchor.BottomCenter))
        {
            AutoHideScrollBar = true
        };
    }

    private static string IngredientName(RecipeIngredient ingredient)
    {
        if (ingredient.Options.Count == 0)
        {
            return string.IsNullOrWhiteSpace(ingredient.Tag)
                ? L.Get("recipe.unknown_ingredient")
                : TextTools.Humanize(ingredient.Tag);
        }
        if (ingredient.Options.Count == 1) { return ingredient.Options[0].Name; }
        return string.Join(" / ", ingredient.Options.Take(3).Select(option => option.Name)) +
               (ingredient.Options.Count > 3 ? " / …" : string.Empty);
    }

    private static IReadOnlyDictionary<string, int> InventoryCounts()
    {
        var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        Character? character = Character.Controlled;
        if (character?.Inventory is null) { return counts; }

        try
        {
            foreach (Item item in character.Inventory.FindAllItems(recursive: true))
            {
                if (item?.Prefab is null) { continue; }
                string identifier = TextTools.NormalizeIdentifier(item.Prefab.Identifier);
                if (identifier.Length == 0) { continue; }
                counts.TryGetValue(identifier, out int existing);
                counts[identifier] = existing + 1;
            }
        }
        catch { }
        return counts;
    }

    private static string CountSignature(TrackedRecipe recipe)
    {
        IReadOnlyDictionary<string, int> counts = InventoryCounts();
        return string.Join(";", recipe.Ingredients.Select(ingredient =>
            ingredient.Key + "=" + ingredient.AcceptedIdentifiers.Sum(
                identifier => counts.TryGetValue(identifier, out int count) ? count : 0)));
    }

    private void DisposeFrame()
    {
        frame?.RectTransform.Parent?.GUIComponent?.RemoveChild(frame);
        frame = null;
        list = null;
        dragHandle = null;
        wasDragging = false;
        lastCountSignature = string.Empty;
    }

    public void Dispose() => DisposeFrame();
}
