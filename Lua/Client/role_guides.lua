-- Editorial summaries based on the official Barotrauma Wiki job pages.
-- Runtime skills and talent trees remain prefab-derived in main.lua.
return {
    captain = {
        responsibilities = {
            "Pilot the submarine and keep the crew informed about contacts, hazards and route changes.",
            "Coordinate priorities during flooding, fires, boarding actions and medical emergencies.",
            "Manage mission decisions, docking and the crew's limited time at outposts.",
        },
        tips = {
            "Use active sonar in short, deliberate sweeps when stealth matters; continuous active sonar advertises the submarine's position.",
            "Call out the direction and distance of threats before changing course so gunners and repair crews can prepare.",
            "Avoid pinning the submarine against terrain. Leave room to descend or reverse if a large creature closes in.",
            "A calm, specific order is more useful than several vague orders. State the problem, location and priority.",
        },
        source = "https://barotraumagame.com/wiki/Captain",
    },
    engineer = {
        responsibilities = {
            "Maintain the reactor, electrical devices, junction boxes and the submarine's power distribution.",
            "Repair electrical equipment and fabricate electrical components, tools and fuel rods.",
            "Diagnose unstable power demand before it becomes a cascade of damaged junction boxes.",
        },
        tips = {
            "Match reactor output to load smoothly; sharp overvoltage is often more destructive than a brief shortage.",
            "Repair high-traffic junction boxes first, then batteries, navigation systems and less critical devices.",
            "Carry a screwdriver, spare wire and suitable protection, but keep emergency fuel rods in a known secure location.",
            "Before rewiring, label the purpose mentally and change one connection at a time so faults remain traceable.",
        },
        source = "https://barotraumagame.com/wiki/Engineer",
    },
    mechanic = {
        responsibilities = {
            "Repair hull breaches and maintain mechanical installations such as pumps, engines and fabricators.",
            "Recover minerals, deconstruct salvage and fabricate mechanical equipment.",
            "Keep ballast spaces, docking areas and external repair routes operational.",
        },
        tips = {
            "Seal the breach before repairing nearby machinery; stopping water ingress changes the entire emergency.",
            "Start with lower hull damage because uncontrolled flooding pulls the submarine deeper and creates more pressure.",
            "Carry a welding tool, wrench and plasma cutter, and verify their fuel or oxygen before leaving the airlock.",
            "Do not stand directly under a breached compartment when opening its door; let pressure and water equalize safely.",
        },
        source = "https://barotraumagame.com/wiki/Mechanic",
    },
    securityofficer = {
        responsibilities = {
            "Operate submarine weapons, repel intruders and protect crew members from internal and external threats.",
            "Maintain ammunition supplies and fabricate weapons or ammunition when qualified.",
            "Control dangerous equipment without obstructing routine crew work.",
        },
        tips = {
            "Identify the target before firing; ammunition, hull integrity and friendly lives are all limited resources.",
            "Call out empty loaders early and stage replacement ammunition near the correct turret without blocking access.",
            "When boarding, protect the medic and retreat through defensible doors instead of chasing creatures alone.",
            "Use stun and restraint tools when lethal force would create a larger problem for the crew.",
        },
        source = "https://barotraumagame.com/wiki/Security_Officer",
    },
    medicaldoctor = {
        responsibilities = {
            "Diagnose and treat injuries, stabilize casualties and keep medical supplies organized.",
            "Fabricate medicine and research or refine genetic material.",
            "Teach the crew which first-aid supplies are safe to use without medical expertise.",
        },
        tips = {
            "Treat the cause that is killing the patient first: oxygen loss, blood loss, burns and internal damage require different responses.",
            "Check existing drug effects before administering more medicine; overdose and addiction can turn treatment into another emergency.",
            "Keep critical drugs in labeled containers and reserve a compact field kit for rescue outside the medical room.",
            "Stabilize several casualties before perfecting one patient's condition during a mass-casualty event.",
        },
        source = "https://barotraumagame.com/wiki/Medical_Doctor",
    },
    assistant = {
        responsibilities = {
            "Support whichever department is overloaded and learn the submarine's layout and emergency procedures.",
            "Move supplies, clean hazards, report damage and perform safe repairs within current skill limits.",
            "Fill operational gaps without taking specialized equipment away from the crew member who needs it.",
        },
        tips = {
            "Ask for a concrete assignment at the start of the round and report when it is complete.",
            "Learn the locations of diving suits, medical care, the reactor, ballast tanks and the main airlocks first.",
            "Carry basic repair tools only when assigned; unnecessary equipment makes shortages harder to diagnose.",
            "The role is flexible, not disposable. Staying alive and communicating clearly is valuable crew support.",
        },
        source = "https://barotraumagame.com/wiki/Assistant",
    },
}
